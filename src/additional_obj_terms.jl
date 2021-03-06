abstract type AbstractEnergyTerm end

"""
Return the integral of the objective function

`_obj_integral(:: AbstractEnergyTerm, :: FEFunctionType, :: AbstractVector)`

See also: `MixedEnergyFETerm`, `EnergyFETerm`, `NoFETerm`,
`_obj_cell_integral`, `_compute_gradient_k`, `_compute_hess_coo`,
`_compute_hess_k_coo`
"""
function _obj_integral end

"""
Return the derivative of the objective function w.r.t. κ.

`_compute_gradient_k(:: AbstractEnergyTerm, :: FEFunctionType, :: AbstractVector)`

See also: `MixedEnergyFETerm`, `EnergyFETerm`, `NoFETerm`, `_obj_integral`,
`_obj_cell_integral`, `_compute_hess_coo`, `_compute_hess_k_coo`
"""
function _compute_gradient_k end

"""
Return the gradient of the objective function and set it in place.

`_compute_gradient!(:: AbstractVector, :: EnergyFETerm, :: AbstractVector, :: FEFunctionType, :: FESpace, :: FESpace)`

See also: `MixedEnergyFETerm`, `EnergyFETerm`, `NoFETerm`, `_obj_integral`,
`_obj_cell_integral`, `_compute_hess_coo`, `_compute_hess_k_coo`
"""
function _compute_gradient! end

#=
"""
Return the hessian w.r.t. yu of the objective function in coo format.

`_compute_hess_coo(:: AbstractEnergyTerm, :: AbstractVector, :: FEFunctionType, :: FESpace, :: FESpace)`

See also: `MixedEnergyFETerm`, `EnergyFETerm`, `NoFETerm`, `_obj_integral`,
`_obj_cell_integral`, `_compute_gradient_k`, `_compute_hess_k_coo`
"""
function _compute_hess_coo end
=#

"""
Return the values of the hessian w.r.t. κ of the objective function.

`_compute_hess_k_vals(:: AbstractNLPModel, :: AbstractEnergyTerm, :: AbstractVector, :: AbstractVector)`

See also: `MixedEnergyFETerm`, `EnergyFETerm`, `NoFETerm`, `_obj_integral`,
`_obj_cell_integral`, `_compute_gradient_k`, `_compute_hess_coo`
"""
function _compute_hess_k_vals end

@doc raw"""
FETerm modeling the objective function when there are no integral objective.

```math
\begin{aligned}
 f(\kappa)
\end{aligned}
 ```

Constructors:

  `NoFETerm()`

  `NoFETerm(:: Function)`

See also: `MixedEnergyFETerm`, `EnergyFETerm`, `_obj_cell_integral`, `_obj_integral`, `_compute_gradient_k!`
"""
struct NoFETerm <: AbstractEnergyTerm
  f::Function
end

function NoFETerm()
  return NoFETerm(x -> 0.0)
end

_obj_integral(term::NoFETerm, κ::AbstractVector, x::FEFunctionType) = term.f(κ)

function _compute_gradient!(
  g::AbstractVector,
  tnrj::NoFETerm,
  κ::AbstractVector,
  yu::FEFunctionType,
  Y::FESpace,
  X::FESpace,
)
  nparam = length(κ)
  nyu = num_free_dofs(Y)
  nvar = nparam + nyu
  @lencheck nvar g

  g[(nparam + 1):nvar] .= zeros(nyu)
  g[1:nparam] .= _compute_gradient_k(tnrj, κ, yu)

  return g
end

function _compute_gradient_k(term::NoFETerm, κ::AbstractVector, yu::FEFunctionType)
  return ForwardDiff.gradient(term.f, κ)
end

#=
function _compute_hess_coo(
  term::NoFETerm,
  κ::AbstractVector{T},
  yu::FEFunctionType,
  Y::FESpace,
  X::FESpace,
) where {T}
  return (Int[], Int[], T[])
end
=#

function _compute_hess_k_vals(
  nlp::AbstractNLPModel,
  term::NoFETerm,
  κ::AbstractVector,
  xyu::AbstractVector,
)
  return LowerTriangular(ForwardDiff.hessian(term.f, κ))[:]
end

@doc raw"""
FETerm modeling the objective function of the optimization problem.

```math
\begin{aligned}
\int_{\Omega} f(y,u) d\Omega,
\end{aligned}
```
where Ω is described by:
 - trian :: Triangulation
 - quad  :: Measure

Constructor:

`EnergyFETerm(:: Function, :: Triangulation, :: Measure)`

See also: MixedEnergyFETerm, NoFETerm, `_obj_cell_integral`, `_obj_integral`,
`_compute_gradient_k!`
"""
struct EnergyFETerm <: AbstractEnergyTerm
  f::Function
  trian::Triangulation # TODO: Is this useful as it is contained in Measure?
  quad::Measure
end

function _obj_integral(term::EnergyFETerm, κ::AbstractVector, x::FEFunctionType)
  @lencheck 0 κ
  return term.f(x) # integrate(term.f(x), term.quad)
end

function _compute_gradient!(
  g::AbstractVector,
  tnrj::EnergyFETerm,
  κ::AbstractVector,
  yu::FEFunctionType,
  Y::FESpace,
  X::FESpace,
)
  @lencheck 0 κ

  cell_yu = Gridap.FESpaces.get_cell_dof_values(yu)
  cell_id_yu = Gridap.Arrays.IdentityVector(length(cell_yu))

  cell_r_yu = get_array(gradient(tnrj.f, yu))
  #Put the result in the format expected by Gridap.FESpaces.assemble_matrix
  vecdata_yu = [[cell_r_yu], [cell_id_yu]] #TODO would replace by Tuple work?
  #Assemble the gradient in the "good" space
  assem = Gridap.FESpaces.SparseMatrixAssembler(Y, X)
  g .= Gridap.FESpaces.assemble_vector(assem, vecdata_yu)

  return g
end

#=
function _compute_gradient_k(term::EnergyFETerm, κ::AbstractVector{T}, yu::FEFunctionType) where {T}
  @lencheck 0 κ
  return T[]
end
=#

#=
function _compute_hess_coo(
  tnrj::EnergyFETerm,
  κ::AbstractVector,
  yu::FEFunctionType,
  Y::FESpace,
  X::FESpace,
)
  @lencheck 0 κ

  cell_yu = Gridap.FESpaces.get_cell_dof_values(yu)
  cell_id_yu = Gridap.Arrays.IdentityVector(length(cell_yu))
  cell_r_yu = get_array(hessian(tnrj.f, yu))
  #Assemble the matrix in the "good" space
  assem = Gridap.FESpaces.SparseMatrixAssembler(Y, X)
  (I, J, V) = assemble_hess(assem, cell_r_yu, cell_id_yu)

  return (I, J, V)
end
=#

function _compute_hess_k_vals(
  nlp::AbstractNLPModel,
  term::EnergyFETerm,
  κ::AbstractVector{T},
  xyu::AbstractVector{T},
) where {T}
  @lencheck 0 κ
  return T[]
end

@doc raw"""
FETerm modeling the objective function of the optimization problem with
functional and discrete unknowns.

```math
\begin{aligned}
\int_{\Omega} f(y,u,\kappa) d\Omega,
\end{aligned}
```
where Ω is described by:
 - trian :: Triangulation
 - quad  :: Measure

Constructor:

`MixedEnergyFETerm(:: Function, :: Triangulation, :: Measure, :: Int)`

See also: `EnergyFETerm`, `NoFETerm`, `_obj_cell_integral`, `_obj_integral`,
`_compute_gradient_k!`
"""
struct MixedEnergyFETerm <: AbstractEnergyTerm
  f::Function
  trian::Triangulation
  quad::Measure

  nparam::Integer #number of discrete unkonwns.

  inde::Bool

  function MixedEnergyFETerm(
    f::Function,
    trian::Triangulation,
    quad::Measure,
    n::Integer,
    inde::Bool,
  )
    @assert n > 0
    return new(f, trian, quad, n, inde)
  end
end

function MixedEnergyFETerm(f::Function, trian::Triangulation, quad::Measure, n::Integer)
  inde = false
  return MixedEnergyFETerm(f, trian, quad, n, inde)
end

function _obj_integral(term::MixedEnergyFETerm, κ::AbstractVector, x::FEFunctionType)
  @lencheck term.nparam κ
  #=kf = interpolate_everywhere(term.ispace, κ)
  return integrate(term.f(kf, x), term.quad)=#
  return term.f(κ, x) # integrate(term.f(κ, x), term.quad)
end

function _compute_gradient!(
  g::AbstractVector,
  term::MixedEnergyFETerm,
  κ::AbstractVector,
  yu::FEFunctionType,
  Y::FESpace,
  X::FESpace,
)
  @lencheck term.nparam κ
  nyu = num_free_dofs(Y)
  @lencheck term.nparam + nyu g

  cell_yu = Gridap.FESpaces.get_cell_dof_values(yu)
  cell_id_yu = Gridap.Arrays.IdentityVector(length(cell_yu))

  cell_r_yu = get_array(gradient(x -> term.f(κ, x), yu))
  #Put the result in the format expected by Gridap.FESpaces.assemble_matrix
  vecdata_yu = [[cell_r_yu], [cell_id_yu]] #TODO would replace by Tuple work?
  #Assemble the gradient in the "good" space
  assem = Gridap.FESpaces.SparseMatrixAssembler(Y, X)
  g[(term.nparam + 1):(term.nparam + nyu)] .= Gridap.FESpaces.assemble_vector(assem, vecdata_yu)

  g[1:(term.nparam)] .= _compute_gradient_k(term, κ, yu)

  return g
end

function _compute_gradient_k(term::MixedEnergyFETerm, κ::AbstractVector, yu::FEFunctionType)
  @lencheck term.nparam κ
  intf = @closure k -> sum(term.f(k, yu)) # sum(integrate(term.f(k, yu), term.quad))
  return ForwardDiff.gradient(intf, κ)
end

#=
function _compute_hess_coo(
  term::MixedEnergyFETerm,
  κ::AbstractVector,
  yu::FEFunctionType,
  Y::FESpace,
  X::FESpace,
)
  cell_yu = Gridap.FESpaces.get_cell_dof_values(yu)
  cell_id_yu = Gridap.Arrays.IdentityVector(length(cell_yu))

  cell_r_yu = get_array(hessian(x -> term.f(κ, x), yu))
  #Assemble the matrix in the "good" space
  assem = Gridap.FESpaces.SparseMatrixAssembler(Y, X)
  (I, J, V) = assemble_hess(assem, cell_r_yu, cell_id_yu)

  return (I, J, V)
end
=#

function _compute_hess_k_vals(
  nlp::AbstractNLPModel,
  term::MixedEnergyFETerm,
  κ::AbstractVector{T},
  xyu::AbstractVector{T},
) where {T}
  inde = (typeof(nlp.tnrj) <: MixedEnergyFETerm && nlp.tnrj.inde) || typeof(nlp.tnrj) <: NoFETerm

  if inde
    nnz = Int(nlp.nparam * (nlp.nparam + 1) / 2)
    prows = nlp.nparam
    yu = FEFunction(nlp.Y, xyu)

    gk = @closure k -> _compute_gradient_k(nlp.tnrj, k, yu)
    Hxk = ForwardDiff.jacobian(gk, κ)
  else
    nnz = Int(nlp.nparam * (nlp.nparam + 1) / 2) + (nlp.meta.nvar - nlp.nparam) * nlp.nparam
    prows = nlp.meta.nvar
    #Hxk = ForwardDiff.jacobian(k -> grad(nlp, vcat(k, xyu)), κ) #doesn't work :(
    function _obj(x)
      κ, xyu = x[1:(nlp.nparam)], x[(nlp.nparam + 1):(nlp.meta.nvar)]
      yu = FEFunction(nlp.Y, xyu)
      int = _obj_integral(nlp.tnrj, κ, yu)
      return sum(int)
    end
    Hxk = ForwardDiff.jacobian(k -> ForwardDiff.gradient(_obj, vcat(k, xyu)), κ)
    #=
    function _grad(k)
        g = similar(k, nlp.meta.nvar)
        _compute_gradient!(g, term, k, yu, nlp.Y, nlp.X)
        return g
    end
    @show _grad(κ), _grad(κ .+ 1.)
    Hxk = ForwardDiff.jacobian(_grad, κ)
    @show Hxk
    =#
    #@show "2nd try:"
    #intf = k -> ForwardDiff.gradient(x -> sum(integrate(term.f(k, x), term.quad)), xyu)
    #Hxk2 = ForwardDiff.jacobian(intf, κ)
    #@show Hxk2
    #We need the gradient w.r.t. yu and then derive by k
  end
  vals = zeros(T, nnz)#Array{T,1}(undef, nnz) #TODO not smart

  # simplify?
  k = 1
  for j = 1:(nlp.nparam)
    for i = j:prows
      if j ≤ i
        vals[k] = Hxk[i, j]
        k += 1
      end
    end
  end

  return vals
end

#=
@doc raw"""
FETerm modeling the objective function of the optimization problem with
functional and discrete unknowns, describe as a norm and a regularizer.

```math
\begin{aligned}
\frac{1}{2}\|Fyu(y,u)\|^2_{L^2_\Omega} + \lambda\int_{\Omega} lyu(y,u) d\Omega
 + \frac{1}{2}\|Fk(κ)\|^2 + \mu lk(κ)
\end{aligned}
```
where Ω is described by:
 - trian :: Triangulation
 - quad  :: Measure

Constructor:

`ResidualEnergyFETerm(:: Function, :: Triangulation, :: Measure, :: Function, :: Int)`

See also: `EnergyFETerm`, `NoFETerm`, `MixedEnergyFETerm`
"""
struct ResidualEnergyFETerm <: AbstractEnergyTerm
  Fyu::Function
  #lyu      :: Function #regularizer
  #λ        :: Real
  trian::Triangulation
  quad::Measure
  Fk::Function
  #lk       :: Function #regularizer
  #μ        :: Real

  nparam::Integer #number of discrete unkonwns.

  #?counters :: NLSCounters #init at NLSCounters()

  function ResidualEnergyFETerm(
    Fyu::Function,
    trian::Triangulation,
    quad::Measure,
    Fk::Function,
    n::Integer,
  )
    @assert n > 0
    return new(Fyu, trian, quad, Fk, n)
  end
end

#TODO: this is specific to ResidualEnergyFETerm
function _jac_residual_yu end
function _jac_residual_k end
function _jprod_residual_yu end
function _jprod_residual_k end
function _jtprod_residual_yu end
function _jtprod_residual_k end
function hess_residual end

function _obj_cell_integral end

function _obj_integral end

function _compute_gradient_k end

function _compute_gradient! end

function _compute_hess_coo end

function _compute_hess_k_coo end

function _compute_hess_k_vals end
=#
