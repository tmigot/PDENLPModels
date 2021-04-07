using Plots, LinearAlgebra, SparseArrays
###############################################################
#Data
x0 = [0.6, 0.1]
N = sum(x0)
T = 7 #final time
###############################################################
#Now we discretize by hand with forward finite differences
n = 10
h = T/n

################################################################
# Using Gridap and PDENLPModels
using Gridap, PDENLPModels

function cell_gridap(x0, n, T)
    kp(x) = 1.01
    kr(x) = 2.03

    model = CartesianDiscreteModel((0,T),n)

    labels = get_face_labeling(model)
    add_tag_from_tags!(labels,"diri0",[1]) #initial time condition

    Vcon = TestFESpace(
            reffe=:Lagrangian, order=1, valuetype=Float64,
            conformity=:L2, model=model)
    Ucon = TrialFESpace(Vcon)
    Xcon = MultiFieldFESpace([Vcon])
    Ycon = MultiFieldFESpace([Ucon])

    function f(yu)
        cf, pf, uf = yu
        kp * pf
    end

    VI = TestFESpace(
        reffe=:Lagrangian, conformity=:H1, valuetype=Float64,
        model=model, labels=labels, order=1, dirichlet_tags=["diri0"]) 
    UI = TrialFESpace(VI, x0[1])
    VS = TestFESpace(
        reffe=:Lagrangian, conformity=:H1, valuetype=Float64,
        model=model, labels=labels, order=1, dirichlet_tags=["diri0"])
    US = TrialFESpace(VS, x0[2])
    Xpde = MultiFieldFESpace([VI, VS])
    Ypde = MultiFieldFESpace([UI, US])

    @law conv(u,∇u) = (∇u ⋅one(∇u))⊙u
    c(u,v) = conv(v,∇(u)) #v⊙conv(u,∇(u))
    function res_pde_nl(yu,v)
        cf, pf, uf = yu
        p, q = v
        #eq. (2) page 3
        c(cf, p) + c(pf, q) - p * ( kp * pf * (1. - cf) - kr * cf * (1. - cf - pf) )
    end
    function res_pde(yu,v)
        cf, pf, uf = yu
        p, q = v
        #eq. (2) page 3
        q * ( uf * kr * cf * (1. - cf - pf) - kp * pf * pf )
    end

    trian = Triangulation(model)
    degree = 1
    quad = CellQuadrature(trian,degree)
    t_Ω_nl = FETerm(res_pde_nl,trian,quad)
    t_Ω = FETerm(res_pde,trian,quad)
    Y = MultiFieldFESpace([UI, US, Ucon])
    op_sir = FEOperator(Ypde,Xpde,t_Ω_nl,t_Ω)

    xin = zeros(Gridap.FESpaces.num_free_dofs(Y))
    nlp = GridapPDENLPModel(xin, f, trian, quad, Ypde, Ycon, Xpde, Xcon, op_sir) 
    return nlp
end

################################################################
# Testing:
using NLPModelsTest, Test

atol, rtol = √eps(), √eps()
n = 10
nlp = cell_gridap(x0, n, T)
xr = rand(nlp.meta.nvar)
#Beta-tests
@test obj(nlp, xr) != nothing
@test grad(nlp, xr) != nothing
@test cons(nlp, xr) != nothing
@test jac(nlp, xr) != nothing
@test hess(nlp, xr) != nothing
@test hess(nlp, xr, nlp.meta.y0) != nothing

#check derivatives
@test gradient_check(nlp, x = xr, atol = atol, rtol = rtol) == Dict{Tuple{Int64,Int64},Float64}()
@test jacobian_check(nlp, x = xr, atol = atol, rtol = rtol) == Dict{Tuple{Int64,Int64},Float64}()
ymp = hessian_check(nlp, x = xr, atol = atol, rtol = rtol)
@test !any(x -> x!=Dict{Tuple{Int64,Int64},Float64}(), values(ymp))
ymp2 = hessian_check_from_grad(nlp, x = xr, atol = atol, rtol = rtol) #uses the jacobian
@test !any(x -> x!=Dict{Tuple{Int64,Int64},Float64}(), values(ymp2))