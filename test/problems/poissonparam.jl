using Gridap, PDENLPModels, LinearAlgebra, SparseArrays, NLPModels, NLPModelsTest, Test

###############################################################################
#
# This test case consider the optimization of a parameter in a Poisson equation
# with Dirichlet boundary conditions.
#
# Aim:
# * Test mixed problem
# * no integral term in the objective function
# * |k| = 1
#
###############################################################################
function poissonparam(args...; n = 3, kwargs...)
    domain = (0,1,0,1)
    partition = (n,n)
    model = CartesianDiscreteModel(domain,partition)
  
    #We use a manufactured solution of the PDE:
    sol(x) = sin(2*pi*x[1]) * x[2]
  
    V0 = TestFESpace(
        reffe=:Lagrangian, order=1, valuetype=Float64,
        conformity=:H1, model=model, dirichlet_tags="boundary")
  
    Ug = TrialFESpace(V0, sol)
  
    trian = Triangulation(model)
    degree = 2
    quad = CellQuadrature(trian,degree)
  
    #We deduce the rhs of the Poisson equation with our manufactured solution:
    f(x) = (2*pi^2) * sin(2*pi*x[1]) * x[2]
  
    function res(k, y, v)
      k1(x) = k[1]
      k1 * ∇(v)⊙∇(y) - v*f
    end
    t_Ω = FETerm(res, trian, quad)
    op = FEOperator(Ug, V0, t_Ω)
  
    fk(k) = 0.5*dot(k .- 1.,k .- 1.)
    nrj = NoFETerm(fk) #length(k)=1
  
    nUg = num_free_dofs(Ug)
    xs  = rand(nUg + 1)
    return GridapPDENLPModel(xs, nrj, Ug, V0, op)
end

function poissonparam_test()
    nlp = poissonparam(n = 5)

    nUg = num_free_dofs(nlp.Ypde)
    x0  = zeros(nUg + 1)
  
    @test nlp.nparam == 1
    x1 = vcat(1., rand(nUg))
    @test obj(nlp, x0) == 0.5
    @test obj(nlp, x1) == 0.
    @test grad(nlp, x0) == vcat(-1., zeros(nUg)) #false
    @test grad(nlp, x1) == vcat( 0., zeros(nUg))
    _Hess = sparse(LowerTriangular(vcat(hcat(1., zeros(1,nUg)), hcat(zeros(nUg,1), zeros(nUg,nUg)))))
    @test hess(nlp, x0) == _Hess
    @test hess(nlp, x1) == _Hess
  
    @test length(cons(nlp, x0)) == nUg
    @test length(cons(nlp, x1)) == nUg
  
    _J0, _J1 = jac(nlp, x0), jac(nlp, x1)
    @test issparse(_J0)
    @test issparse(_J1)
    @test size(_J0) == (nUg, nUg + 1)
    @test size(_J1) == (nUg, nUg + 1)
  
    @test hprod(nlp, x1, zeros(nUg + 1)) == zeros(nUg + 1)
    vr = rand(nUg + 1)
    @test hprod(nlp, x1, vr) == hess(nlp, x1) * vr #hess is a diagonal matrix
  
    l = rand(nUg)
    @test hprod(nlp, x1, l, zeros(nUg + 1)) == zeros(nUg + 1)
    @test hprod(nlp, x1, l, vr) ≈ Symmetric(hess(nlp, x1, l), :L) * vr atol = 1e-14

end

poissonparam_test()
nlp = poissonparam()
check_nlp_dimensions(nlp)
view_subarray_nlp(nlp)
coord_memory_nlp(nlp)
consistent_nlps([nlp, nlp])