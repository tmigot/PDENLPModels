using Gridap, Test
n = 512
domain = (0,1)
partition = n#(n,n)
model = CartesianDiscreteModel(domain,partition)

labels = get_face_labeling(model)
add_tag_from_tags!(labels,"diri1",[2])
add_tag_from_tags!(labels,"diri0",[1])

D = 1
order = 1
V = TestFESpace(
  reffe=:Lagrangian, conformity=:H1, valuetype=Float64,
  model=model, labels=labels, order=order, dirichlet_tags=["diri0","diri1"])

h(x) = 2*(nu + x[1]^3)
uD0 = VectorValue(0)
uD1 = VectorValue(-1)
U = TrialFESpace(V,[uD0,uD1])

@law conv(u,∇u) = (∇u ⋅one(∇u))⊙u
@law dconv(du,∇du,u,∇u) = conv(u,∇du)+conv(du,∇u)

function a(u,v)
  ∇(v)⊙∇(u)
end

c(u,v) = v⊙conv(u,∇(u))
nu = 0.08
function res_pde(u,v)
  z(x) = 0.5
  -nu*(∇(v)⊙∇(u)) + c(u,v) - v * z - v * h
end

trian = Triangulation(model)
@test Gridap.FESpaces.num_cells(trian) == 512
degree = 1
quad = CellQuadrature(trian,degree)
t_Ω = FETerm(res_pde,trian,quad)
op_pde = FEOperator(U,V,t_Ω)

#Check resolution for z given.
using LineSearches: BackTracking
nls = NLSolver(
  show_trace=true, method=:newton, linesearch=BackTracking())
solver = FESolver(nls)

uh = solve(solver,op_pde)
sol_gridap = vcat(get_free_values(uh), 0.5*ones(513))

#Now we move to the optimization:
ud(x) = -x[1]^2
α = 1e-2

#objective function:
f(u, z) = 0.5 * (ud - u) * (ud - u) + 0.5 * α * z * z
function f(yu) #:: Union{Gridap.MultiField.MultiFieldFEFunction, Gridap.CellData.GenericCellField}
    u, z = yu
    f(u,z)
end

function res(yu, v) #u is the solution of the PDE and z the control
 u, z = yu
 v

 -nu*(∇(v)⊙∇(u)) + c(u,v) - v * z - v * h
end
t_Ω = FETerm(res,trian,quad)
op = FEOperator(U, V, t_Ω)

Xcon = TestFESpace(
        reffe=:Lagrangian, order=1, valuetype=Float64,
        conformity=:H1, model=model)
Ycon = TrialFESpace(Xcon)

@test Gridap.FESpaces.num_free_dofs(U) < Gridap.FESpaces.num_free_dofs(Ycon)
#################################################################################

using NLPModels, Krylov, Main.PDENLPModels
Y = MultiFieldFESpace([U, Ycon])
xin = zeros(Gridap.FESpaces.num_free_dofs(Y))
@warn "Fix GridapPDENLPModel to let Yedp and Ycon be SingleFieldFESpace!"
@time nlp = GridapPDENLPModel(xin, zeros(0), f, MultiFieldFESpace([U]), MultiFieldFESpace([Ycon]), V, Xcon, trian, quad, op = op)

@test nlp.meta.nvar == 1024
@test nlp.meta.ncon == 511

@time _Hx = hess(nlp, sol_gridap)
@test issymmetric(_Hx)

#Test hprod
#hprod!(nlp  :: GridapPDENLPModel, x :: AbstractVector, λ :: AbstractVector, v :: AbstractVector, Hv :: AbstractVector

#For Fletcher_penalty_solver take sigma = 10^3,
#(0,0) as initial guess, and B1 approximation of the hessian.
#
#include("../../FletcherPenaltyNLPSolver/src/large-scale-Newton.jl")
#x, fx, norm∇x, ncx = solver_eq(nlp) #hess_op is not available

#include("../../FletcherPenaltyNLPSolver/src/FletcherPenaltyNLPSolver.jl")

nothing