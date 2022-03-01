module MeltingParam

# If you want to add a new method here, feel free to do so. 
# Remember to also export the function name in GeoParams.jl (in addition to here)

using Parameters, LaTeXStrings, Unitful
using ..Units
using GeoParams: AbstractMaterialParam, PhaseDiagram_LookupTable, AbstractMaterialParamsStruct
import Base.show, GeoParams.param_info
using ..MaterialParameters: MaterialParamsInfo

abstract type AbstractMeltingParam{T} <: AbstractMaterialParam end

export  compute_meltfraction, 
        compute_meltfraction!,    # calculation routines
        param_info,
        MeltingParam_Caricchi     # constant
        
include("../Utils.jl")
include("../Computations.jl")

# Constant  -------------------------------------------------------
"""
    MeltingParam_Caricchi()
    
Implements the T-dependent melting parameterisation used by Caricchi et al 
```math  
    \\theta = (800.0 .- (T + 273.15))./23.0 
```
```math  
    \\phi_{solid} = 1.0 - {1.0 \\over (1.0 + e^\\theta)}; 
```

Note that T is in Kelvin.

"""
@with_kw_noshow struct MeltingParam_Caricchi{T,U} <: AbstractMeltingParam{T}
    a::GeoUnit{T,U}              =   800.0K              
    b::GeoUnit{T,U}              =   23.0K
    c::GeoUnit{T,U}              =   273.15K # shift from C to K
end
MeltingParam_Caricchi(args...) = MeltingParam_Caricchi(convert.(GeoUnit,args)...)

function param_info(s::MeltingParam_Caricchi) # info about the struct
    return MaterialParamsInfo(Equation =  L"\phi = {1 \over {1 + \exp( {800-T[^oC] \over 23})}}")
end

# Calculation routine
function compute_meltfraction(p::MeltingParam_Caricchi{_T}, P::Quantity, T::Quantity) where _T
    @unpack_units a,b,c   = p

    θ       =   (a - (T - c))/b
    ϕ       =   1.0./(1.0 .+ exp.(θ))

    return ϕ
end


function compute_meltfraction(p::MeltingParam_Caricchi{_T}, P::_T, T::_T ) where _T
    @unpack_val a,b,c   = p

    θ       =   (a - (T - c))/b
    return 1.0/(1.0 + exp(θ))
end


function compute_meltfraction!(ϕ::AbstractArray{_T}, p::MeltingParam_Caricchi{_T}, P::AbstractArray{_T}, T::AbstractArray{_T}) where _T
    @unpack_val a,b,c   = p
    
    @. ϕ = 1.0/(1.0 + exp((a-(T-c))/b)) 

    return nothing
end

# Print info 
function show(io::IO, g::MeltingParam_Caricchi)  
    print(io, "Caricchi et al. melting parameterization")  
end
#-------------------------------------------------------------------------


"""
    ComputeMeltingParam(P,T, p::AbstractPhaseDiagramsStruct)

Computes melt fraction in case we use a phase diagram lookup table. The table should have the collum `:meltFrac` specified.
"""
function compute_meltfraction(p::PhaseDiagram_LookupTable, P::_T,T::_T) where _T
   return p.meltFrac.(T,P)
end

"""
    ComputeMeltingParam!(ϕ::AbstractArray{<:AbstractFloat}, P::AbstractArray{<:AbstractFloat},T:AbstractArray{<:AbstractFloat}, p::PhaseDiagram_LookupTable)

In-place computation of melt fraction in case we use a phase diagram lookup table. The table should have the collum `:meltFrac` specified.
"""
function compute_meltfraction!(ϕ::AbstractArray{_T}, p::PhaseDiagram_LookupTable, P::AbstractArray{_T}, T::AbstractArray{_T}) where _T
    ϕ[:]    =   p.meltFrac.(T,P)

    return nothing
end

# Computational routines needed for computations with the MaterialParams structure 
function compute_meltfraction(s::AbstractMaterialParamsStruct, P::_T=zero(_T),T::_T=zero(_T)) where {_T}
    if isempty(s.Melting) #in case there is a phase with no melting parametrization
        return zero(_T)
    end
    return compute_meltfraction(s.Melting[1], P,T)
end

"""
    ComputeMeltingParam!(ϕ::AbstractArray{<:AbstractFloat}, Phases::AbstractArray{<:Integer}, P::AbstractArray{<:AbstractFloat},T::AbstractArray{<:AbstractFloat}, MatParam::AbstractArray{<:AbstractMaterialParamsStruct})

In-place computation of density `rho` for the whole domain and all phases, in case a vector with phase properties `MatParam` is provided, along with `P` and `T` arrays.
"""
compute_meltfraction(args...) = compute_param(compute_meltfraction, args...)
compute_meltfraction!(args...) = compute_param!(compute_meltfraction, args...)

#=
function compute_meltfraction!(ϕ::AbstractArray{<:AbstractFloat, N}, MatParam::AbstractArray{<:AbstractMaterialParamsStruct, 1}, Phases::AbstractArray{<:Integer, N}, P::AbstractArray{<:AbstractFloat, N},T::AbstractArray{<:AbstractFloat, N}) where N

    for i = 1:length(MatParam)

        if length(MatParam[i].Melting)>0

            # Create views into arrays (so we don't have to allocate)
            ind = Phases .== MatParam[i].Phase;
            ϕ_local   =   view(ϕ, ind )
            P_local   =   view(P  , ind )
            T_local   =   view(T  , ind )

            compute_meltfraction!(ϕ_local, MatParam[i].Melting[1], P_local, T_local) 
        end

    end

    return nothing
end


"""
    ComputeMeltingParam!(ϕ::AbstractArray{<:AbstractFloat}, Phases::AbstractArray{<:AbstractFloat}, P::AbstractArray{<:AbstractFloat},T::AbstractArray{<:AbstractFloat}, MatParam::AbstractArray{<:AbstractMaterialParamsStruct})

In-place computation of density `rho` for the whole domain and all phases, in case a vector with phase properties `MatParam` is provided, along with `P` and `T` arrays.
"""
function compute_meltfraction!(ϕ::AbstractArray{<:AbstractFloat, N}, MatParam::AbstractArray{<:AbstractMaterialParamsStruct, 1}, PhaseRatios::AbstractArray{<:AbstractFloat, M}, P::AbstractArray{<:AbstractFloat, N},T::AbstractArray{<:AbstractFloat, N}) where {N,M}

    ϕ .= 0.0
    for i = 1:length(MatParam)
        
        ϕ_local  = zeros(size(ϕ))
        Fraction    = selectdim(PhaseRatios,M,i);
        if (maximum(Fraction)>0.0) & (length(MatParam[i].Melting)>0)

            compute_meltfraction!(ϕ_local, MatParam[i].Melting[1] , P, T) 

            ϕ .= ϕ .+ ϕ_local.*Fraction
        end

    end

    return nothing
end
=#


end