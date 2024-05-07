#[allow(unused_use)]
/// This module contains the implementation of the flight booking system.
/// It defines the data structures and functions necessary for creating airlines, passengers,
/// booking flights, and managing balances.
module flight_booking::flight_booking {

    // Imports
    use sui::transfer;
    use sui::sui::SUI;
    use std::string::{Self, String};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use sui::table::{Self, Table};

    // Errors
    const EInsufficientFunds: u64 = 1;
    const EInvalidCoin: u64 = 2;
    const ENotPassenger: u64 = 3;
    const EInvalidFlight: u64 = 4;
    const ENotAirline: u64 = 5;
    const EInvalidFlightBooking: u64 = 6;

    // FlightBooking Airline 

    /// Represents an airline in the flight booking system.
    struct Airline has key {
        id: UID,
        name: String,
        flight_prices: Table<ID, u64>, // flight_id -> price
        balance: Balance<SUI>,
        memos: Table<ID, FlightMemo>, // flight_id -> memo
        airline: address
    }

    // Passenger

    /// Represents a passenger in the flight booking system.
    struct Passenger has key {
        id: UID,
        name: String,
        passenger: address,
        airline_id: ID,
        balance: Balance<SUI>,
    }

    // FlightMemo

    /// Represents a memo for a flight in the flight booking system.
    struct FlightMemo has key, store {
        id: UID,
        flight_id: ID,
        ticket_price: u64,
        airline: address 
    }

    // Flight

    /// Represents a flight in the flight booking system.
    struct Flight has key {
        id: UID,
        flight_number: String,
        destination : String,
        departure_time: u64,
        airline: address,
        available_seats: u64,
    }

    // Record of Flight Booking

    /// Represents a booking record in the flight booking system.
    struct BookingRecord has key, store {
        id: UID,
        passenger_id: ID,
        flight_id: ID,
        passenger: address,
        airline: address,
        paid_amount: u64,
        ticket_price: u64,
        booking_time: u64
    }

    // Create a new Airline object 

    /// Creates a new airline object with the given name.
    /// The airline object is added to the shared object pool.
    public fun create_airline(ctx:&mut TxContext, name: String) {
        let airline = Airline {
            id: object::new(ctx),
            name: name,
            flight_prices: table::new<ID, u64>(ctx),
            balance: balance::zero<SUI>(),
            memos: table::new<ID, FlightMemo>(ctx),
            airline: tx_context::sender(ctx)
        };

        transfer::share_object(airline);
    }

    // Create a new Passenger object

    /// Creates a new passenger object with the given name and airline address.
    /// The passenger object is added to the shared object pool.
    public fun create_passenger(ctx:&mut TxContext, name: String, airline_address: address) {
        let airline_id_: ID = object::id_from_address(airline_address);
        let passenger = Passenger {
            id: object::new(ctx),
            name: name,
            passenger: tx_context::sender(ctx),
            airline_id: airline_id_,
            balance: balance::zero<SUI>(),
        };

        transfer::share_object(passenger);
    }

    // create a memo for a flight

    /// Creates a memo for a flight and adds it to the airline's memo table.
    /// Returns the created flight object.
    public fun create_flight_memo(
        airline: &mut Airline,
        ticket_price: u64,
        flight_number: String,
        destination: String,
        departure_time: u64,
        ctx: &mut TxContext
    ): Flight {
        assert!(airline.airline == tx_context::sender(ctx), ENotAirline);
        let flight = Flight {
            id: object::new(ctx),
            flight_number: flight_number,
            destination: destination,
            departure_time: departure_time,
            airline: airline.airline,
            available_seats: 100 // Assuming each flight initially has 100 available seats
        };
        let memo = FlightMemo {
            id: object::new(ctx),
            flight_id: object::uid_to_inner(&flight.id),
            ticket_price: ticket_price,
            airline: airline.airline
        };

        table::add<ID, FlightMemo>(&mut airline.memos, object::uid_to_inner(&flight.id), memo);

        flight
    }

    // Book a flight

    /// Books a flight for a passenger and updates the booking record and balances.
    /// Returns the payment amount as a Coin<SUI>.
    public fun book_flight(
        airline: &mut Airline,
        passenger: &mut Passenger,
        flight: &mut Flight,
        flight_memo_id: ID,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<SUI> {
        assert!(airline.airline == tx_context::sender(ctx), ENotAirline);
        assert!(passenger.airline_id == object::id_from_address(airline.airline), ENotPassenger);
        assert!(table::contains<ID, FlightMemo>(&airline.memos, flight_memo_id), EInvalidFlightBooking);
        assert!(flight.airline == airline.airline, EInvalidFlight);
        assert!(flight.available_seats > 0, EInvalidFlight);
        let flight_id = &flight.id;
        let memo = table::borrow<ID, FlightMemo>(&airline.memos, flight_memo_id);

        let passenger_id = object::uid_to_inner(&passenger.id);
        
        let ticket_price = memo.ticket_price;
        let booking_time = clock::timestamp_ms(clock);
        let booking_record = BookingRecord {
            id: object::new(ctx),
            passenger_id:passenger_id ,
            flight_id: object::uid_to_inner(flight_id),
            passenger: passenger.passenger,
            airline: airline.airline,
            paid_amount: ticket_price,
            ticket_price: ticket_price,
            booking_time: booking_time
        };

        transfer::public_freeze_object(booking_record);
        // deduct the ticket price from the passenger balance and add it to the airline balance
        assert!(ticket_price <= balance::value(&passenger.balance), EInsufficientFunds);
        let amount_to_pay = coin::take(&mut passenger.balance, ticket_price, ctx);
        let same_amount_to_pay = coin::take(&mut passenger.balance, ticket_price, ctx);
        assert!(coin::value(&amount_to_pay) > 0, EInvalidCoin);
        assert!(coin::value(&same_amount_to_pay) > 0, EInvalidCoin);

        transfer::public_transfer(amount_to_pay, airline.airline);

        same_amount_to_pay
    }

    // Passenger adding funds to their account

    /// Adds funds to the passenger's balance.
    public fun top_up_passenger_balance(
        passenger: &mut Passenger,
        amount: Coin<SUI>,
        ctx: &mut TxContext
    ){
        assert!(passenger.passenger == tx_context::sender(ctx), ENotPassenger);
        balance::join(&mut passenger.balance, coin::into_balance(amount));
    }

    // add the Payment fee to the airline balance

    /// Adds the payment fee to the airline's balance.
    public fun top_up_airline_balance(
        airline: &mut Airline,
        passenger: &mut Passenger,
        flight: &mut Flight,
        flight_memo_id: ID,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        // Can only be called by the passenger
        assert!(passenger.passenger == tx_context::sender(ctx), ENotPassenger);
        let (amount_to_pay) = book_flight(airline, passenger, flight, flight_memo_id, clock, ctx);
        balance::join(&mut airline.balance, coin::into_balance(amount_to_pay));
    }

    // Get the balance of the airline

    /// Returns a reference to the balance of the airline.
    public fun get_airline_balance(airline: &Airline) : &Balance<SUI> {
        &airline.balance
    }

    // Airline can withdraw the balance

    /// Allows the airline to withdraw funds from its balance.
    public fun withdraw_funds(
        airline: &mut Airline,
        amount: u64,
        ctx: &mut TxContext
    ){
        assert!(airline.airline == tx_context::sender(ctx), ENotAirline);
        assert!(amount <= balance::value(&airline.balance), EInsufficientFunds);
        let amount_to_withdraw = coin::take(&mut airline.balance, amount, ctx);
        transfer::public_transfer(amount_to_withdraw, airline.airline);
    }
    
    // Transfer the Ownership of the flight to the passenger

    /// Transfers the ownership of a flight to a passenger.
    public entry fun transfer_flight_ownership(
        passenger: &Passenger,
        flight: Flight,
    ){
        transfer::transfer(flight, passenger.passenger);
    }


    // Passenger Returns the flight ownership
    // Increase the available seats in the flight

    /// Returns the ownership of a flight by a passenger and increases the available seats.
    public fun return_flight(
        airline: &mut Airline,
        passenger: &mut Passenger,
        flight: &mut Flight,
        ctx: &mut TxContext
    ) {
        assert!(airline.airline == tx_context::sender(ctx), ENotAirline);
        assert!(passenger.airline_id == object::id_from_address(airline.airline), ENotPassenger);
        assert!(flight.airline == airline.airline, EInvalidFlight);

        flight.available_seats = flight.available_seats + 1;
    }  
}
