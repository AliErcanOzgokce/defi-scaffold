module defi_scaffold::dex_utils {
    use sui::coin::{Coin};
    use defi_scaffold::dex_core::{
        TradingPair, 
        PairRegistry, 
        LiquidityToken, 
        AdminCap
    };
    use defi_scaffold::dex_helper::safe_transfer;

    // ================================
    // Convenience Functions for SDK
    // ================================

    /// Creates a pair and transfers LP tokens to sender
    public fun create_pair_and_transfer<TokenA, TokenB>(
        registry: &mut PairRegistry,
        token_a: Coin<TokenA>,
        token_b: Coin<TokenB>,
        fee_rate_bps: u64,
        ctx: &mut TxContext,
    ) {
        // Call dex_core::create_pair
        let lp_tokens = registry.create_pair(
            token_a,
            token_b,
            fee_rate_bps,
            ctx
        );
        
        // Transfer LP tokens to sender
        safe_transfer(lp_tokens, ctx.sender());
    }

    /// Adds liquidity and transfers results to sender
    public fun add_liquidity_and_transfer<TokenA, TokenB>(
        pair: &mut TradingPair<TokenA, TokenB>,
        token_a: Coin<TokenA>,
        token_b: Coin<TokenB>,
        min_liquidity: u64,
        ctx: &mut TxContext,
    ) {
        // Call dex_core::add_liquidity
        let (remaining_a, remaining_b, lp_tokens) = pair.add_liquidity( 
            token_a, 
            token_b,
            min_liquidity,
            ctx
        );
        
        // Transfer to sender
        let sender = ctx.sender();
        safe_transfer(remaining_a, sender);
        safe_transfer(remaining_b, sender);
        safe_transfer(lp_tokens, sender);
    }

    /// Removes liquidity and transfers tokens to sender
    public fun remove_liquidity_and_transfer<TokenA, TokenB>(
        pair: &mut TradingPair<TokenA, TokenB>,
        liquidity_tokens: Coin<LiquidityToken<TokenA, TokenB>>,
        min_amount_a: u64,
        min_amount_b: u64,
        ctx: &mut TxContext,
    ) {
        // Call dex_core::remove_liquidity
        let (token_a, token_b) = pair.remove_liquidity(
            liquidity_tokens,
            min_amount_a,
            min_amount_b,
            ctx
        );
        
        // Transfer to sender
        safe_transfer(token_a, ctx.sender());
        safe_transfer(token_b, ctx.sender());
    }

    /// Swaps A to B and transfers result to sender
    public fun swap_a_to_b_and_transfer<TokenA, TokenB>(
        pair: &mut TradingPair<TokenA, TokenB>,
        token_a: Coin<TokenA>,
        min_amount_out: u64,
        ctx: &mut TxContext,
    ) {
        // Call dex_core::swap_a_to_b
        let token_b = pair.swap_a_to_b( token_a, min_amount_out, ctx);
        
        // Transfer result to sender
        safe_transfer(token_b, ctx.sender());
    }

    /// Swaps B to A and transfers result to sender
    public fun swap_b_to_a_and_transfer<TokenA, TokenB>(
        pair: &mut TradingPair<TokenA, TokenB>,
        token_b: Coin<TokenB>,
        min_amount_out: u64,
        ctx: &mut TxContext,
    ) {
        // Call dex_core::swap_b_to_a
        let token_a = pair.swap_b_to_a(token_b, min_amount_out, ctx);
        
        // Transfer result to sender
        safe_transfer(token_a, ctx.sender());
    }

    /// Collects admin fees and transfers to sender
    public fun collect_fees_and_transfer<TokenA, TokenB>(
        pair: &mut TradingPair<TokenA, TokenB>,
        admin_cap: &AdminCap,
        ctx: &mut TxContext,
    ) {
        // Call dex_core::collect_fees
        let (fee_a, fee_b) = pair.collect_fees(admin_cap, ctx);
        
        // Transfer fees to sender
        safe_transfer(fee_a, ctx.sender());
        safe_transfer(fee_b, ctx.sender());
    }
} 