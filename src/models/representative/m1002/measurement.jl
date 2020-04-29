"""
```
measurement(m::Model1002{T}, TTT::Matrix{T}, RRR::Matrix{T},
            CCC::Vector{T}) where {T<:AbstractFloat}
```

Assign measurement equation

```
y_t = ZZ*s_t + DD + u_t
```

where

```
Var(ϵ_t) = QQ
Var(u_t) = EE
Cov(ϵ_t, u_t) = 0
```
"""
function measurement(m::Model1002{T},
                     TTT::Matrix{T},
                     RRR::Matrix{T},
                     CCC::Vector{T}; reg::Int = 1) where {T<:AbstractFloat}

    endo     = m.endogenous_states
    endo_new = m.endogenous_states_augmented
    exo      = m.exogenous_shocks
    obs      = m.observables

    _n_observables = n_observables(m)
    _n_states = n_states_augmented(m)
    _n_shocks_exogenous = n_shocks_exogenous(m)

    ZZ = zeros(_n_observables, _n_states)
    DD = zeros(_n_observables)
    EE = zeros(_n_observables, _n_observables)
    QQ = zeros(_n_shocks_exogenous, _n_shocks_exogenous)

    for para in m.parameters
        if !isempty(para.regimes)
            ModelConstructors.toggle_regime!(para, reg)
        end
    end

    no_integ_inds = inds_states_no_integ_series(m)
    if get_setting(m, :add_laborproductivity_measurement)
        # Remove integrated states (e.g. states w/unit roots)
        TTT = @view TTT[no_integ_inds, no_integ_inds]
        CCC = @view CCC[no_integ_inds]
    end

    ## GDP growth - Quarterly!
    ZZ[obs[:obs_gdp], endo[:y_t]]          = 1.0
    ZZ[obs[:obs_gdp], endo_new[:y_t1]]     = -1.0
    ZZ[obs[:obs_gdp], endo[:z_t]]          = 1.0
    ZZ[obs[:obs_gdp], endo_new[:e_gdp_t]]  = 1.0
    ZZ[obs[:obs_gdp], endo_new[:e_gdp_t1]] = -m[:me_level]
    DD[obs[:obs_gdp]]                      = 100*(exp(m[:z_star])-1)

    ## GDI growth- Quarterly!
    ZZ[obs[:obs_gdi], endo[:y_t]]          = m[:γ_gdi]
    ZZ[obs[:obs_gdi], endo_new[:y_t1]]     = -m[:γ_gdi]
    ZZ[obs[:obs_gdi], endo[:z_t]]          = m[:γ_gdi]
    ZZ[obs[:obs_gdi], endo_new[:e_gdi_t]]  = 1.0
    ZZ[obs[:obs_gdi], endo_new[:e_gdi_t1]] = -m[:me_level]
    DD[obs[:obs_gdi]]                      = 100*(exp(m[:z_star])-1) + m[:δ_gdi]

    ## Hours growth
    ZZ[obs[:obs_hours], endo[:L_t]] = 1.0
    DD[obs[:obs_hours]]             = m[:Lmean]

    ## Labor Share/real wage growth
    if subspec(m) in ["ss16", "ss17"]
        # log(labor_share) = log(wage) + log(hours) - log(GDP)
        ZZ[obs[:obs_laborshare], endo[:w_t]] = 1.
        ZZ[obs[:obs_laborshare], endo[:L_t]] = 1.
        DD[obs[:obs_laborshare]] = 100. * log(m[:wstar] * m[:Lstar] / m[:ystar])
        ZZ[obs[:obs_laborshare], endo[:y_t]] = -1.
    else
        ZZ[obs[:obs_wages], endo[:w_t]]      = 1.0
        ZZ[obs[:obs_wages], endo_new[:w_t1]] = -1.0
        ZZ[obs[:obs_wages], endo[:z_t]]      = 1.0
        DD[obs[:obs_wages]]                  = 100*(exp(m[:z_star])-1)
    end
    ## Inflation (GDP Deflator)
    ZZ[obs[:obs_gdpdeflator], endo[:π_t]]            = m[:Γ_gdpdef]
    ZZ[obs[:obs_gdpdeflator], endo_new[:e_gdpdef_t]] = 1.0
    DD[obs[:obs_gdpdeflator]]                        = 100*(m[:π_star]-1) + m[:δ_gdpdef]

    ## Inflation (Core PCE)
    ZZ[obs[:obs_corepce], endo[:π_t]]             = 1.0
    ZZ[obs[:obs_corepce], endo_new[:e_corepce_t]] = 1.0
    DD[obs[:obs_corepce]]                         = 100*(m[:π_star]-1)

    ## Nominal interest rate
    ZZ[obs[:obs_nominalrate], endo[:R_t]] = 1.0
    DD[obs[:obs_nominalrate]]             = m[:Rstarn]

    ## Consumption Growth
    ZZ[obs[:obs_consumption], endo[:c_t]]      = 1.0
    ZZ[obs[:obs_consumption], endo_new[:c_t1]] = -1.0
    ZZ[obs[:obs_consumption], endo[:z_t]]      = 1.0
    DD[obs[:obs_consumption]]                  = 100*(exp(m[:z_star])-1)

    ## Investment Growth
    ZZ[obs[:obs_investment], endo[:i_t]]      = 1.0
    ZZ[obs[:obs_investment], endo_new[:i_t1]] = -1.0
    ZZ[obs[:obs_investment], endo[:z_t]]      = 1.0
    DD[obs[:obs_investment]]                  = 100*(exp(m[:z_star])-1)

    ## Spreads
    ZZ[obs[:obs_spread], endo[:ERtil_k_t]] = 1.0
    ZZ[obs[:obs_spread], endo[:R_t]]       = -1.0
    DD[obs[:obs_spread]]                   = 100*log(m[:spr])

    ## 10 yrs infl exp

    TTT10                          = (1/40)*((Matrix{Float64}(I, size(TTT, 1), size(TTT,1))
                                              - TTT)\(TTT - TTT^41))
    ZZ[obs[:obs_longinflation], :] = TTT10[endo[:π_t], :]
    DD[obs[:obs_longinflation]]    = 100*(m[:π_star]-1)

    ## Long Rate
    ZZ[obs[:obs_longrate], :]               = ZZ[6, :]' * TTT10
    ZZ[obs[:obs_longrate], endo_new[:e_lr_t]] = 1.0
    DD[obs[:obs_longrate]]                  = m[:Rstarn]

    ## TFP
    ZZ[obs[:obs_tfp], endo[:z_t]]       = (1-m[:α])*m[:Iendoα] + 1*(1-m[:Iendoα])
    if subspec(m) in ["ss14", "ss15", "ss16", "ss18", "ss19"]
        ZZ[obs[:obs_tfp], endo_new[:e_tfp_t]]  = 1.0
        ZZ[obs[:obs_tfp], endo_new[:e_tfp_t1]] = -m[:me_level]
    else
        ZZ[obs[:obs_tfp], endo_new[:e_tfp_t]] = 1.0
    end
    if !(subspec(m) in ["ss15", "ss16"])
        ZZ[obs[:obs_tfp], endo[:u_t]]       = m[:α]/( (1-m[:α])*(1-m[:Iendoα]) + 1*m[:Iendoα] )
        ZZ[obs[:obs_tfp], endo_new[:u_t1]]  = -(m[:α]/( (1-m[:α])*(1-m[:Iendoα]) + 1*m[:Iendoα]) )
    end

    if subspec(m) in ["ss60"]
        QQ[exo[:ziid_sh], exo[:ziid_sh]] = m[:σ_ziid]^2
        QQ[exo[:biid_sh], exo[:biid_sh]] = m[:σ_biid]^2
        QQ[exo[:biidc_sh], exo[:biidc_sh]] = m[:σ_biidc]^2
        QQ[exo[:σ_ωiid_sh], exo[:σ_ωiid_sh]] = m[:σ_σ_ωiid]^2
        QQ[exo[:λ_wiid_sh], exo[:λ_wiid_sh]] = m[:σ_λ_wiid]^2
        QQ[exo[:φ_sh], exo[:φ_sh]] = m[:σ_φ]^2
    end

    QQ[exo[:g_sh], exo[:g_sh]]            = m[:σ_g]^2
    QQ[exo[:b_sh], exo[:b_sh]]            = m[:σ_b]^2
    QQ[exo[:μ_sh], exo[:μ_sh]]            = m[:σ_μ]^2
    QQ[exo[:ztil_sh], exo[:ztil_sh]]      = m[:σ_ztil]^2
    QQ[exo[:λ_f_sh], exo[:λ_f_sh]]        = m[:σ_λ_f]^2
    QQ[exo[:λ_w_sh], exo[:λ_w_sh]]        = m[:σ_λ_w]^2
    QQ[exo[:rm_sh], exo[:rm_sh]]          = m[:σ_r_m]^2
    QQ[exo[:σ_ω_sh], exo[:σ_ω_sh]]        = m[:σ_σ_ω]^2
    QQ[exo[:μ_e_sh], exo[:μ_e_sh]]        = m[:σ_μ_e]^2
    QQ[exo[:γ_sh], exo[:γ_sh]]            = m[:σ_γ]^2
    QQ[exo[:π_star_sh], exo[:π_star_sh]]  = m[:σ_π_star]^2
    QQ[exo[:lr_sh], exo[:lr_sh]]          = m[:σ_lr]^2
    QQ[exo[:zp_sh], exo[:zp_sh]]          = m[:σ_z_p]^2
    QQ[exo[:tfp_sh], exo[:tfp_sh]]        = m[:σ_tfp]^2
    QQ[exo[:gdpdef_sh], exo[:gdpdef_sh]]  = m[:σ_gdpdef]^2
    QQ[exo[:corepce_sh], exo[:corepce_sh]]= m[:σ_corepce]^2
    QQ[exo[:gdp_sh], exo[:gdp_sh]]        = m[:σ_gdp]^2
    QQ[exo[:gdi_sh], exo[:gdi_sh]]        = m[:σ_gdi]^2

    if subspec(m) == "ss52"
        # Add in wage markup shocks as an additional observable
        ZZ[obs[:obs_wagemarkupshock], endo[:ϵ_λ_w_t]] = 1.
    end
    if subspec(m) == "ss53"
        # Add in wage markup as an additional observable
        ZZ[obs[:obs_wagemarkup], endo[:λ_w_t]] = 1.
    end
    if subspec(m) == "ss56"
        # Add in wage markup as an additional observable
        ZZ[obs[:obs_ztil], endo[:ztil_t]] = 1.
    end
    if subspec(m) == "ss57"
        # Add in wage markup as an additional observable
        ZZ[obs[:obs_ztilshock], endo[:ϵ_ztil_t]] = 1.
    end
    if subspec(m) in ["ss58", "ss59", "ss60"]
        # Add in wage markup as an additional observable
        ZZ[obs[:obs_ztil], endo[:ztil_t]] = 1.
        ZZ[obs[:obs_z], endo[:z_t]] = 1.
        # DD[obs[:obs_z]] = 100. * (exp(m[:z_star]) - 1.)
        ZZ[obs[:obs_zp], endo[:zp_t]] = 1.
    end
    if subspec(m) == "ss59"
        ZZ[obs[:obs_b], endo[:b_t]] = 1.
    end

    if subspec(m) in ["ss60"]
        ZZ[obs[:obs_ziid], endo[:ziid_t]] = 1.
        ZZ[obs[:obs_biid], endo[:biid_t]] = 1.
        ZZ[obs[:obs_biidc], endo[:biidc_t]] = 1.
        ZZ[obs[:obs_sigma_omegaiid], endo[:σ_ωiid_t]] = 1.
        ZZ[obs[:obs_sigma_omega], endo[:σ_ω_t]] = 1.
        ZZ[obs[:obs_b], endo[:b_t]] = 1.
        ZZ[obs[:obs_lambda_wiid], endo[:λ_wiid_t]] = 1.
        ZZ[obs[:obs_lambda_w], endo[:λ_w_t]] = 1.
        ZZ[obs[:obs_varphi], endo[:φ_t]] = 1.
    end


   # These lines set the standard deviations for the anticipated shocks
    for i = 1:n_mon_anticipated_shocks(m)
        ZZ[obs[Symbol("obs_nominalrate$i")], :] = ZZ[obs[:obs_nominalrate], no_integ_inds]' * (TTT^i)
        DD[obs[Symbol("obs_nominalrate$i")]]    = m[:Rstarn]
        if subspec(m) == "ss11"
            QQ[exo[Symbol("rm_shl$i")], exo[Symbol("rm_shl$i")]] = m[:σ_r_m]^2 / n_mon_anticipated_shocks(m)
        else
            QQ[exo[Symbol("rm_shl$i")], exo[Symbol("rm_shl$i")]] = m[Symbol("σ_r_m$i")]^2
        end
    end

    for (k, v) in get_setting(m, :antshocks)
        if k == :z # z is a sum of a transient and persistent component, so we model this differently
            for i = 1:v
                ZZ[obs[Symbol("obs_z$i")], no_integ_inds] = ZZ[obs[:obs_z], no_integ_inds]' * (TTT^i)
                # DD[obs[Symbol("obs_z$i")]]    = 100. * (exp(m[:z_star]) - 1.)
                if subspec(m) == "ss11"
                    QQ[exo[Symbol("z_shl$i")], exo[Symbol("z_shl$i")]] = m[:σ_ztil]^2 / v
                else
                    QQ[exo[Symbol("z_shl$i")], exo[Symbol("z_shl$i")]] = m[Symbol("σ_z$i")]^2
                end
            end
        else
            for i = 1:v
                ZZ[obs[Symbol("obs_", k, "$i")], no_integ_inds] = ZZ[obs[Symbol(:obs_, k)], no_integ_inds]' * (TTT^i)
                if subspec(m) == "ss11"
                    QQ[exo[Symbol(k, "_shl$i")], exo[Symbol(k, "_shl$i")]] = m[Symbol(:σ_, k)]^2 / v
                else
                    QQ[exo[Symbol(k, "_shl$i")], exo[Symbol(k, "_shl$i")]] = m[Symbol("σ_", k, "$i")]^2
                end
            end
        end
    end


    # Adjustment to DD because measurement equation assumes CCC is the zero vector
    if any(CCC .!= 0)
        DD += ZZ*((UniformScaling(1) - TTT)\CCC)
    end

    for para in m.parameters
        if !isempty(para.regimes)
            ModelConstructors.toggle_regime!(para, 1)
        end
    end

    return Measurement(ZZ, DD, QQ, EE)
end
