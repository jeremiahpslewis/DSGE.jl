using DSGE, Test, CSV, DataFrames
using ModelConstructors, Nullables, Dates, OrderedCollections

prob_vecs = [[1., 0.], [.5, .5], [0., 1.]]
Hbar_vec = [14, 10, 6]

m = Model1002("ss59"; custom_settings = Dict{Symbol, Setting}(:flexible_ait_2020Q3_policy_change =>
                                                              Setting(:flexible_ait_2020Q3_policy_change,
                                                                      false),
                                                              :add_pgap => Setting(:add_pgap, false),
                                                              :add_ygap => Setting(:add_ygap, false),
                                                              :add_altpolicy_pgap => Setting(:add_altpolicy_pgap, true),
                                                              :add_altpolicy_ygap => Setting(:add_altpolicy_ygap, true))) # Set to false unless you want to re-generate any saved output
m <= Setting(:flexible_ait_2020Q3_policy_change, false) # Set to false unless you want to re-generate any saved output
m <= Setting(:date_forecast_start, Date(2020, 6, 30))
m <= Setting(:date_conditional_end, Date(2020, 6, 30))
m <= Setting(:cond_full_names, [:obs_gdp, :obs_corepce, :obs_spread, # Have to add anticipated rates to conditional data
                                   :obs_nominalrate, :obs_longrate,
                                   :obs_nominalrate1, :obs_nominalrate2, :obs_nominalrate3,
                                   :obs_nominalrate4, :obs_nominalrate5, :obs_nominalrate6])
m <= Setting(:cond_semi_names, [:obs_spread,
                                   :obs_nominalrate, :obs_longrate,
                                   :obs_nominalrate1, :obs_nominalrate2, :obs_nominalrate3,
                                   :obs_nominalrate4, :obs_nominalrate5, :obs_nominalrate6])

output_vars = [:histobs, :forecastobs, :histpseudo, :forecastpseudo]

df_full = DataFrame(CSV.read(joinpath(dirname(@__FILE__), "../reference/uncertain_altpolicy_data.csv")))
modal_params = map(x -> x.value, m.parameters)

hist_rule = get_setting(m, :alternative_policy)
setup_regime_switching_inds!(m; cond_type = :full) # Reset the regime dates b/c using full conditional forecast

# Set up parameters
for j in 5:30 # Just add a bunch
    ModelConstructors.set_regime_val!(m[:σ_g], j, m[:σ_g].value)
    ModelConstructors.set_regime_val!(m[:σ_b], j, m[:σ_b].value)
    ModelConstructors.set_regime_val!(m[:σ_μ], j, m[:σ_μ].value)
    ModelConstructors.set_regime_val!(m[:σ_ztil], j, m[:σ_ztil].value)
    ModelConstructors.set_regime_val!(m[:σ_λ_f], j, m[:σ_λ_f].value)
    ModelConstructors.set_regime_val!(m[:σ_λ_w], j, m[:σ_λ_w].value)
    ModelConstructors.set_regime_val!(m[:σ_r_m], j, m[:σ_r_m].value)
    ModelConstructors.set_regime_val!(m[:σ_σ_ω], j, m[:σ_σ_ω].value)
    ModelConstructors.set_regime_val!(m[:σ_μ_e], j, m[:σ_μ_e].value)
    ModelConstructors.set_regime_val!(m[:σ_γ], j, m[:σ_γ].value)
    ModelConstructors.set_regime_val!(m[:σ_π_star], j, m[:σ_π_star].value)
    ModelConstructors.set_regime_val!(m[:σ_lr], j, m[:σ_lr].value)
    ModelConstructors.set_regime_val!(m[:σ_z_p], j, m[:σ_z_p].value)
    ModelConstructors.set_regime_val!(m[:σ_tfp], j, m[:σ_tfp].value)
    ModelConstructors.set_regime_val!(m[:σ_gdpdef], j, m[:σ_gdpdef].value)
    ModelConstructors.set_regime_val!(m[:σ_corepce], j, m[:σ_corepce].value)
    ModelConstructors.set_regime_val!(m[:σ_gdp], j, m[:σ_gdp].value)
    ModelConstructors.set_regime_val!(m[:σ_gdi], j, m[:σ_gdi].value)

    for l = 1:DSGE.n_mon_anticipated_shocks(m)
        ModelConstructors.set_regime_val!(m[Symbol("σ_r_m$(l)")], j, m[Symbol("σ_r_m$(l)")].value)
    end

    ModelConstructors.set_regime_val!(m[:σ_φ], j, 0.)
    ModelConstructors.set_regime_val!(m[:σ_biidc], j, 0.)
    ModelConstructors.set_regime_val!(m[:σ_ziid], j, 0.)
    if haskey(m.keys, :σ_φ_prop)
        ModelConstructors.set_regime_val!(m[:σ_φ_prop], j, 0.)
    end
    if haskey(m.keys, :σ_biidc_prop)
        ModelConstructors.set_regime_val!(m[:σ_biidc_prop], j, 0.)
    end
    if haskey(m.keys, :σ_ziid_prop)
        ModelConstructors.set_regime_val!(m[:σ_ziid_prop], j, 0.)
    end
end

# Impose the historical policy as the permanent and "alternative" rule
T_unc = Dict()
R_unc = Dict()
C_unc = Dict()
for j in 1:length(prob_vecs)
    m <= Setting(:alternative_policy_weights, prob_vecs[j])
    T_unc[j], R_unc[j], C_unc[j] = DSGE.gensys_uncertain_altpol(m, prob_vecs[j], DSGE.AltPolicy[hist_rule],
                                                                apply_altpolicy = true)
    T_unc[j], R_unc[j], C_unc[j] = DSGE.augment_states(m, T_unc[j], R_unc[j], C_unc[j])
end

# Some setup
tempZLB_regimes = Dict()
m <= Setting(:alternative_policies, AltPolicy[hist_rule])

autoTs = Dict() # automatically calculated, these are what we are testing
autoRs = Dict()
autoCs = Dict()
auto_fcasts = Dict()

manTs = Dict()  # manually calculated, these are the "truth"
manRs = Dict()
manCs = Dict()
fcasts = Dict()

# Calculate baseline forecast to calculate the states in 2020-Q3
baseline_fcasts = DSGE.forecast_one_draw(m, :mode, :full, vcat(:forecaststates, output_vars), modal_params,
                                         df_full; regime_switching = true, n_regimes =
                                         get_setting(m, :n_regimes))

# Now calculate everything else
for j in 1:length(prob_vecs)
    m <= Setting(:alternative_policy_weights, prob_vecs[j])

    # Set up initial state
    s₀ = baseline_fcasts[:forecaststates][:, 1]

    # Set up temporary ZLB regimes
    tempZLB_regimes[j] = 4:(4 + Hbar_vec[j] - 1)
    new_regime_dates = Dict{Int, Date}()
    new_regime_dates[1] = date_presample_start(m)
    for (regind, date) in zip(2:(maximum(tempZLB_regimes[j]) + 1), # This won't actually go to 3000, but this makes sure we have
                              Date(2020, 3, 31):Dates.Month(3):Date(3000,3,31)) # enough regimes to fill up hist_regime_dates properly
        new_regime_dates[regind] = date
    end

    m <= Setting(:regime_dates, new_regime_dates)
    setup_regime_switching_inds!(m; cond_type = :full)

    m <= Setting(:replace_eqcond, true)
    m <= Setting(:gensys2, true)
    replace_eqcond = Dict{Int, Function}()     # Which rule to replace with in which periods
    for regind in tempZLB_regimes[j]
        replace_eqcond[regind] = DSGE.zero_rate_replace_eq_entries # Temp ZLB rule in this regimes
    end
    # replace_eqcond[tempZLB_regimes[j]] = DSGE.eqcond # Will set the "lift-off" regime directly
    m <= Setting(:replace_eqcond_func_dict, replace_eqcond)
    fcasts[j] = deepcopy(baseline_fcasts)

    # Set up matrices for regime-switching. Note that we have
    # plus 1 for lift-off b/c historical and conditional forecast period are accounted for by fact
    # tempZLB_regimes calculated from forecastobs (which includes conditional forecast periods)
    Γ0s = Vector{Matrix{Float64}}(undef, maximum(tempZLB_regimes[j]) + 1)
    Γ1s = Vector{Matrix{Float64}}(undef, maximum(tempZLB_regimes[j]) + 1)
    Cs = Vector{Vector{Float64}}(undef, maximum(tempZLB_regimes[j]) + 1)
    Ψs = Vector{Matrix{Float64}}(undef, maximum(tempZLB_regimes[j]) + 1)
    Πs = Vector{Matrix{Float64}}(undef, maximum(tempZLB_regimes[j]) + 1)

    TTTs_uzlb = Vector{Matrix{Float64}}(undef, maximum(tempZLB_regimes[j]) + 1) # uncertain ZLB
    RRRs_uzlb = Vector{Matrix{Float64}}(undef, maximum(tempZLB_regimes[j]) + 1)
    CCCs_uzlb = Vector{Vector{Float64}}(undef, maximum(tempZLB_regimes[j]) + 1)

    # Automatic calculation
    m <= Setting(:uncertain_altpolicy, true)
    m <= Setting(:uncertain_zlb, true)
    autoTs[j], autoRs[j], autoCs[j] = solve(m; apply_altpolicy = true, regime_switching = true,
                                            hist_regimes = collect(1:get_setting(m, :n_hist_regimes)),
                                            fcast_regimes =
                                            collect((get_setting(m, :n_hist_regimes) + 1):get_setting(m, :n_regimes)),
                                            regimes = collect(1:get_setting(m, :n_regimes)))
    auto_fcasts[j] = DSGE.forecast_one_draw(m, :mode, :full, output_vars, modal_params,
                                                                                df_full; regime_switching = true, n_regimes =
                                                                                get_setting(m, :n_regimes))
    m <= Setting(:uncertain_altpolicy, false) # Need to turn these off afterward
    m <= Setting(:uncertain_zlb, false)

    # Onto the manual calculation

    # Only need to fill up the matrices for the forecast regimes for this part
    for fcast_reg in 3:length(TTTs_uzlb)
        Γ0s[fcast_reg], Γ1s[fcast_reg], Cs[fcast_reg], Ψs[fcast_reg], Πs[fcast_reg] =
            eqcond(m, fcast_reg)
    end
    TTT_gensys_final, RRR_gensys_final, CCC_gensys_final = solve(m; apply_altpolicy = true)
    TTT_gensys_final = TTT_gensys_final[1:n_states(m), 1:n_states(m)]
    RRR_gensys_final = RRR_gensys_final[1:n_states(m), :]
    CCC_gensys_final = CCC_gensys_final[1:n_states(m)]

    # Calculate temp ZLB regimes under assumption smooth AIT-GDP occurs forever after ZLB ends
    gensys2_regimes = (tempZLB_regimes[j][1] - 1):(tempZLB_regimes[j][end] + 1)
    Tcal, Rcal, Ccal = DSGE.gensys_cplus(m, Γ0s[gensys2_regimes], Γ1s[gensys2_regimes],
                                         Cs[gensys2_regimes], Ψs[gensys2_regimes], Πs[gensys2_regimes],
                                         TTT_gensys_final, RRR_gensys_final, CCC_gensys_final)
    Tcal[end] = TTT_gensys_final
    Rcal[end] = RRR_gensys_final
    Ccal[end] = CCC_gensys_final

    Th, Rh, Ch = hist_rule.solve(m)

    # Prep for calculation of new transition matrices
    Γ0_til, Γ1_til, Γ2_til, C_til, Ψ_til = DSGE.gensys_to_predictable_form(Γ0s[4], Γ1s[4], Cs[4], Ψs[4], Πs[4])

    # Get new transition matrices for "uncertain" ZLB
    # Note we pass in Tcal[2:end] since we want the period t + 1 ZLB matrix for period t.
    # TTTs_uzlb[inreg] is the same size as Tcal though b/c TTTs_uzbl[inreg[end]] is just Tcal[end], etc.
    inreg = gensys2_regimes[2:end]
    TTTs_uzlb[inreg], RRRs_uzlb[inreg], CCCs_uzlb[inreg] =
        DSGE.gensys_uncertain_zlb(prob_vecs[j], Th[1:n_states(m), 1:n_states(m)],
                                  Ch[1:n_states(m)], Tcal[2:end], Rcal[2:end], Ccal[2:end],
                                  Γ0_til, Γ1_til, Γ2_til, C_til, Ψ_til)
    for li in inreg
        TTTs_uzlb[li], RRRs_uzlb[li], CCCs_uzlb[li] = DSGE.augment_states(m, TTTs_uzlb[li], RRRs_uzlb[li], CCCs_uzlb[li])
    end

    # Now update the last regime matrices to feature "uncertainty" about the alt policy, too, post ZLB
    TTTs_uzlb[end] = T_unc[j]
    RRRs_uzlb[end] = R_unc[j]
    CCCs_uzlb[end] = C_unc[j]

    manTs[j] = TTTs_uzlb
    manRs[j] = RRRs_uzlb
    manCs[j] = CCCs_uzlb

    meass = map(x -> measurement(m, TTTs_uzlb[x], RRRs_uzlb[x], CCCs_uzlb[x]), 4:length(TTTs_uzlb))
    pseus = map(x -> pseudo_measurement(m, TTTs_uzlb[x], RRRs_uzlb[x], CCCs_uzlb[x]), 4:length(TTTs_uzlb))

    for (lj, tempZLB_reg) in enumerate(tempZLB_regimes[j])
        mreg = tempZLB_reg - 2 # first conditional period is already counted

        s₁ = TTTs_uzlb[tempZLB_reg] * s₀ + CCCs_uzlb[tempZLB_reg]
        fcasts[j][:forecastobs][:, mreg] = meass[lj][:ZZ] * s₁ + meass[lj][:DD]
        fcasts[j][:forecastpseudo][:, mreg] = pseus[lj][:ZZ_pseudo] * s₁ + pseus[lj][:DD_pseudo]
        s₀ .= s₁
    end

    # After the first period post the conditional forecast, we now assume we use the uncertain historical rule
    for t in (maximum(tempZLB_regimes[j]) - 2 + 1):(1 + forecast_horizons(m, cond_type = :full))
        s₁ = TTTs_uzlb[end] * s₀ + CCCs_uzlb[end]
        fcasts[j][:forecastobs][:, t] = meass[end][:ZZ] * s₁ + meass[end][:DD]
        fcasts[j][:forecastpseudo][:, t] = pseus[end][:ZZ_pseudo] * s₁ + pseus[end][:DD_pseudo]
        s₀ .= s₁
    end
end

@testset "Check automatic calculation of uncertain ZLB with an uncertain alternative policy." begin
    for j in 1:length(prob_vecs)
        for i in 4:length(manTs[j])
            @test @test_matrix_approx_eq autoTs[j][i] manTs[j][i]
        end
        @test @test_matrix_approx_eq fcasts[j][:forecastobs] auto_fcasts[j][:forecastobs]
        @test @test_matrix_approx_eq fcasts[j][:histpseudo] auto_fcasts[j][:histpseudo]
        @test @test_matrix_approx_eq fcasts[j][:forecastpseudo] auto_fcasts[j][:forecastpseudo]
    end
end

nothing
