function GridapPDENLPModel(x0    :: AbstractVector{T},
                           tnrj  :: NRJ,
                           Ypde  :: FESpace,
                           Xpde  :: FESpace;
                           lvar  :: AbstractVector = - T(Inf) * ones(T, length(x0)), #Union{AbstractVector, Function}
                           uvar  :: AbstractVector =   T(Inf) * ones(T, length(x0)), #Union{AbstractVector, Function}
                           name  :: String = "Generic") where {T, NRJ <: AbstractEnergyTerm}

  nvar = length(x0)

  #_xpde = typeof(Xpde) <: MultiFieldFESpace ? Xpde : MultiFieldFESpace([Xpde])
  X = Xpde #_xpde
  #_ypde = typeof(Ypde) <: MultiFieldFESpace ? Ypde : MultiFieldFESpace([Ypde])
  Y = Ypde #_ypde
  nvar_pde = Gridap.FESpaces.num_free_dofs(Ypde)
  nvar_con = 0
  nparam   = nvar - (nvar_pde + nvar_con)

  @assert nparam ≥ 0 throw(DimensionError("x0", nvar_pde, nvar))

  nnzh = get_nnzh(tnrj, Ypde, Xpde, nparam, nvar) #nvar * (nvar + 1) / 2

  if NRJ <: NoFETerm && typeof(lvar) <: AbstractVector && typeof(uvar) <: AbstractVector
    lv, uv = lvar, uvar
  else
    lv, uv = bounds_functions_to_vectors(Y, VoidFESpace(), Ypde, tnrj.trian, lvar, uvar, T[], T[])
  end

  @lencheck nvar x0 lv uv

  meta = NLPModelMeta(nvar, x0=x0, lvar=lv, uvar=uv, nnzh=nnzh,
                      minimize=true, islp=false, name=name)

  return GridapPDENLPModel(meta, Counters(), tnrj, Ypde, VoidFESpace(), Xpde, VoidFESpace(),
                           Y, X, nothing, nvar_pde, nvar_con, nparam)
end

function GridapPDENLPModel(x0    :: AbstractVector{T},
                           f     :: Function,
                           trian :: Triangulation,
                           quad  :: CellQuadrature,
                           Ypde  :: FESpace,
                           Xpde  :: FESpace;
                           lvar  :: AbstractVector = - T(Inf) * ones(T, length(x0)), #Union{AbstractVector, Function}
                           uvar  :: AbstractVector =   T(Inf) * ones(T, length(x0)), #Union{AbstractVector, Function}
                           name  :: String = "Generic") where T

  nvar_pde = Gridap.FESpaces.num_free_dofs(Ypde)
  nparam   = length(x0) - nvar_pde

  tnrj = nparam > 0 ? MixedEnergyFETerm(f, trian, quad, nparam) : EnergyFETerm(f, trian, quad)

  return GridapPDENLPModel(x0, tnrj, Ypde, Xpde, lvar = lvar, uvar = uvar, name = name)
end

function GridapPDENLPModel(x0    :: AbstractVector{T},
                           f     :: Function,
                           trian :: Triangulation,
                           quad  :: CellQuadrature,
                           Ypde  :: FESpace,
                           Xpde  :: FESpace,
                           c     :: FEOperator;
                           lvar  :: AbstractVector = - T(Inf) * ones(T, length(x0)), #Union{AbstractVector, Function}
                           uvar  :: AbstractVector =   T(Inf) * ones(T, length(x0)), #Union{AbstractVector, Function}
                           name  :: String = "Generic") where T

  nvar_pde = Gridap.FESpaces.num_free_dofs(Ypde)
  nparam   = length(x0) - nvar_pde

  tnrj = nparam > 0 ? MixedEnergyFETerm(f, trian, quad, nparam) : EnergyFETerm(f, trian, quad)

  return GridapPDENLPModel(x0, tnrj, Ypde, Xpde, c, lvar = lvar, uvar = uvar, name = name)
end

function GridapPDENLPModel(x0    :: AbstractVector{T},
                           tnrj  :: NRJ,
                           Ypde  :: FESpace,
                           Xpde  :: FESpace,
                           c     :: FEOperator;
                           lvar  :: AbstractVector = - T(Inf) * ones(T, length(x0)), #Union{AbstractVector, Function}
                           uvar  :: AbstractVector =   T(Inf) * ones(T, length(x0)), #Union{AbstractVector, Function}
                           name  :: String = "Generic",
                           lin   :: AbstractVector{<: Integer} = Int[]) where {T, NRJ <: AbstractEnergyTerm}
  
  npde  = Gridap.FESpaces.num_free_dofs(Ypde)
  ndisc = length(x0) - npde

  return return GridapPDENLPModel(x0, tnrj, Ypde, VoidFESpace(), Xpde, VoidFESpace(), c;
                                  lvary = lvar[1:npde], uvary = uvar[1:npde], 
                                  lvark = lvar[npde+1:npde+ndisc], uvark = uvar[npde+1:npde+ndisc], 
                                  name = name, lin = lin)
end

function GridapPDENLPModel(x0    :: AbstractVector{T},
                           tnrj  :: NRJ,
                           Ypde  :: FESpace,
                           Ycon  :: FESpace,
                           Xpde  :: FESpace,
                           Xcon  :: FESpace,
                           c     :: FEOperator;
                           lvary :: AbstractVector = - T(Inf) * ones(T, num_free_dofs(Ypde)), #Union{AbstractVector, Function}
                           uvary :: AbstractVector =   T(Inf) * ones(T, num_free_dofs(Ypde)), #Union{AbstractVector, Function}
                           lvaru :: AbstractVector = - T(Inf) * ones(T, num_free_dofs(Ycon)), #Union{AbstractVector, Function}
                           uvaru :: AbstractVector =   T(Inf) * ones(T, num_free_dofs(Ycon)), #Union{AbstractVector, Function}
                           lvark :: AbstractVector = - T(Inf) * ones(T, max(length(x0) - num_free_dofs(Ypde) - num_free_dofs(Ycon),0)),
                           uvark :: AbstractVector =   T(Inf) * ones(T, max(length(x0) - num_free_dofs(Ypde) - num_free_dofs(Ycon),0)),
                           lcon  :: AbstractVector = zeros(T, num_free_dofs(Ypde)),
                           ucon  :: AbstractVector = zeros(T, num_free_dofs(Ypde)),
                           y0    :: AbstractVector = zeros(T, num_free_dofs(Ypde)),
                           name  :: String = "Generic",
                           lin   :: AbstractVector{<: Integer} = Int[]) where {T, NRJ <: AbstractEnergyTerm}

  nvar = length(x0)
  ncon = length(lcon)

  nvar_pde = num_free_dofs(Ypde)
  nvar_con = num_free_dofs(Ycon)
  nparam   = nvar - (nvar_pde + nvar_con)

  @assert nparam>=0 throw(DimensionError("x0", nvar_pde + nvar_con, nvar))

  if !(typeof(Xcon) <: VoidFESpace) && !(typeof(Ycon) <: VoidFESpace)
    _xpde = _fespace_to_multifieldfespace(Xpde)
    _xcon = _fespace_to_multifieldfespace(Xcon)
    #Handle the case where Ypde or Ycon are single field FE space(s).
    _ypde = _fespace_to_multifieldfespace(Ypde)
    _ycon = _fespace_to_multifieldfespace(Ycon)
    #Build Y (resp. X) the trial (resp. test) space of the Multi Field function [y,u]
    X     = MultiFieldFESpace(vcat(_xpde.spaces, _xcon.spaces))
    Y     = MultiFieldFESpace(vcat(_ypde.spaces, _ycon.spaces))
  elseif (typeof(Xcon) <: VoidFESpace) ⊻ (typeof(Ycon) <: VoidFESpace)
    throw(ErrorException("Error: Xcon or Ycon are both nothing or must be specified."))
  else
    #_xpde = _fespace_to_multifieldfespace(Xpde)
    X = Xpde #_xpde
    #_ypde = _fespace_to_multifieldfespace(Ypde)
    Y = Ypde #_ypde
  end

  if NRJ == NoFETerm && typeof(lvary) <: AbstractVector && typeof(uvary) <: AbstractVector
    lvar, uvar = vcat(lvary, lvaru, lvark), vcat(uvary, uvaru, uvark)
  elseif NRJ != NoFETerm
    fun_lvar, fun_uvar = bounds_functions_to_vectors(Y, Ycon, Ypde, tnrj.trian, lvary, uvary, lvaru, uvaru)
    lvar, uvar = vcat(fun_lvar, lvark), vcat(fun_uvar, uvark)
  else #NRJ == FETerm and 
    #NotImplemented: NoFETerm and functional bounds
    @warn "GridapPDENLPModel: NotImplemented NoFETerm and functional bounds, ignores the functional bounds"
    #In theory can be taken from Operator but it depends which type.
    lvar, uvar = - T(Inf) * ones(T, nvar), T(Inf) * ones(T, nvar)
  end

  @lencheck nvar lvar uvar
  @lencheck ncon ucon y0

  nnzh = get_nnzh(tnrj, c, Y, X, nparam, nvar) #nvar * (nvar + 1) / 2
 
  if typeof(c) <: AffineFEOperator #Here we expect ncon = nvar_pde
    nln = Int[]
    lin = 1:ncon
  else
    nln = setdiff(1:ncon, lin)
  end
  nnz_jac_k = nparam > 0 ? ncon * nparam : 0
  nnzj = count_nnz_jac(c, Y, Xpde, Ypde, Ycon) + nnz_jac_k

  meta = NLPModelMeta(nvar, x0=x0, lvar=lvar, uvar=uvar, ncon=ncon,
                      y0=y0, lcon=lcon, ucon=ucon, nnzj=nnzj, nnzh=nnzh, lin=lin,
                      nln=nln, minimize=true, islp=false, name=name)

  return GridapPDENLPModel(meta, Counters(), tnrj, Ypde, Ycon, Xpde, Xcon, Y, X,
                           c, nvar_pde, nvar_con, nparam)
end

function GridapPDENLPModel(x0    :: AbstractVector{T},
                           f     :: Function,
                           trian :: Triangulation,
                           quad  :: CellQuadrature,
                           Ypde  :: FESpace,
                           Ycon  :: FESpace,
                           Xpde  :: FESpace,
                           Xcon  :: FESpace,
                           c     :: FEOperator;
                           lvary :: AbstractVector = - T(Inf) * ones(T, num_free_dofs(Ypde)), #Union{AbstractVector, Function}
                           uvary :: AbstractVector =   T(Inf) * ones(T, num_free_dofs(Ypde)), #Union{AbstractVector, Function}
                           lvaru :: AbstractVector = - T(Inf) * ones(T, num_free_dofs(Ycon)), #Union{AbstractVector, Function}
                           uvaru :: AbstractVector =   T(Inf) * ones(T, num_free_dofs(Ycon)), #Union{AbstractVector, Function}
                           lvark :: AbstractVector = - T(Inf) * ones(T, max(length(x0) - num_free_dofs(Ypde) - num_free_dofs(Ycon),0)),
                           uvark :: AbstractVector =   T(Inf) * ones(T, max(length(x0) - num_free_dofs(Ypde) - num_free_dofs(Ycon),0)),
                           lcon  :: AbstractVector = zeros(T, num_free_dofs(Ypde)),
                           ucon  :: AbstractVector = zeros(T, num_free_dofs(Ypde)),
                           y0    :: AbstractVector = zeros(T, num_free_dofs(Ypde)),
                           name  :: String = "Generic",
                           lin   :: AbstractVector{<: Integer} = Int[]) where T

  nvar     = length(x0)
  nvar_pde = num_free_dofs(Ypde)
  nvar_con = num_free_dofs(Ycon)
  nparam   = nvar - (nvar_pde + nvar_con)

  tnrj = nparam > 0 ? MixedEnergyFETerm(f, trian, quad, nparam) : EnergyFETerm(f, trian, quad)

  return GridapPDENLPModel(x0, tnrj, Ypde, Ycon, Xpde, Xcon, c, 
                           lvary = lvary, uvary = uvary,
                           lvaru = lvaru, uvaru = uvaru, 
                           lcon = lcon, ucon = ucon, y0 = y0, 
                           name = name, lin = lin)
end