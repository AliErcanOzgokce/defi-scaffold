module defi_scaffold::dex_helper {
    use std::u128::sqrt;
    use sui::coin::{Self, Coin};
    
    // ================================
    // Constants
    // ================================
    const MAX_FEE_BPS: u64 = 10000; // 10000 = 100%
    /// Minimum liquidity to prevent division by zero
    const MIN_LIQUIDITY: u64 = 1000;
    
    // ================================
    // Helper Functions
    // ================================

    /// Calculates initial liquidity based on input amounts
    public(package) fun calculate_initial_liquidity(
        amount_a: u64,
        amount_b: u64
    ): u64 {
        // Initial liquidity is geometric mean of amounts
        // L = sqrt(a * b)
        let product = sqrt((amount_a as u128) * (amount_b as u128));
        
        // Ensure minimum liquidity
        if (product < (MIN_LIQUIDITY as u128)) {
            MIN_LIQUIDITY
        } else {
            (product as u64)
        }
    }

    /// Calculates liquidity amount for additional deposits
    public(package) fun calculate_liquidity_amount(
        amount_a: u64,
        amount_b: u64,
        reserve_a: u64,
        reserve_b: u64,
        liquidity_supply: u64,
    ): u64 {
        let a_ratio = (amount_a as u128) * (liquidity_supply as u128) / (reserve_a as u128);
        let b_ratio = (amount_b as u128) * (liquidity_supply as u128) / (reserve_b as u128);
        if (a_ratio < b_ratio) {
            (a_ratio as u64)
        } else {
            (b_ratio as u64)
        }
    }

    /// Calculates withdrawal amounts for removing liquidity
    public(package) fun calculate_withdrawal_amounts(
        lp_amount: u64,
        reserve_a: u64,
        reserve_b: u64,
        liquidity_supply: u64,
    ): (u64, u64) {
        let amount_a = (lp_amount as u128) * (reserve_a as u128) / (liquidity_supply as u128);
        let amount_b = (lp_amount as u128) * (reserve_b as u128) / (liquidity_supply as u128);
        
        ((amount_a as u64), (amount_b as u64))
    }

    /// Calculates optimal deposit amounts for existing pair
    public(package) fun calculate_deposit_amounts(
        amount_a: u64,
        amount_b: u64,
        reserve_a: u64,
        reserve_b: u64,
    ): (u64, u64) {
        // No reserves yet
        if (reserve_a == 0 && reserve_b == 0) {
            return (amount_a, amount_b)
        };

        // Calculate optimal deposit amounts based on the current ratio
        let optimal_b = (amount_a as u128) * (reserve_b as u128) / (reserve_a as u128);

        if ((optimal_b as u64) <= amount_b) {
            // Need more of token A, use all of token A
            (amount_a, (optimal_b as u64))
        } else {
            // Need more of token B, calculate reverse ratio
            let optimal_a = (amount_b as u128) * (reserve_a as u128) / (reserve_b as u128);
            ((optimal_a as u64), amount_b)
        }
    }

    /// Calculates swap output using constant product formula
    public(package) fun calculate_swap_output(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
        fee_rate_bps: u64,
    ): u64 {
        // Calculate fee
        let fee_amount = amount_in * fee_rate_bps / MAX_FEE_BPS;
        let amount_in_with_fee = amount_in - fee_amount;

        // Apply constant product formula: (x + dx) * (y - dy) = x * y
        // dy = y * dx / (x + dx)
        let numerator = (amount_in_with_fee as u128) * (reserve_out as u128);
        let denominator = (reserve_in as u128) + (amount_in_with_fee as u128);
        
        (numerator / denominator) as u64
    }

    /// Calculates protocol fees and LP fees
    public(package) fun calculate_protocol_fees(
        amount_in: u64,
        protocol_fee_bps: u64,
    ): (u64, u64) {
        let protocol_fee = amount_in * protocol_fee_bps / MAX_FEE_BPS;
        let lp_fee = amount_in - protocol_fee;
        (protocol_fee, lp_fee)
    }

    /// Calculates input after fees and fee amount
    public(package) fun calculate_input_fees(
        amount_in: u64,
        fee_rate_bps: u64,
    ): (u64, u64) {
        let fee_amount = amount_in * fee_rate_bps / MAX_FEE_BPS;
        (amount_in - fee_amount, fee_amount)
    }

    /// Safely transfers a coin to recipient, destroying if zero
    public(package) fun safe_transfer<T>(coin: Coin<T>, recipient: address) {
        if (coin::value(&coin) > 0) {
            transfer::public_transfer(coin, recipient);
        } else {
            coin::destroy_zero(coin);
        }
    }
} 