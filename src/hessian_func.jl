"""
These functions:
https://github.com/gridap/Gridap.jl/blob/758a8620756e164ba0e6b83dc8dcbb278015b3d9/src/FESpaces/SparseMatrixAssemblers.jl#L463

https://github.com/gridap/Gridap.jl/blob/758a8620756e164ba0e6b83dc8dcbb278015b3d9/src/Algebra/SparseMatrixCSC.jl

https://github.com/gridap/Gridap.jl/blob/758a8620756e164ba0e6b83dc8dcbb278015b3d9/src/Algebra/SparseMatrices.jl#L29-L33
"""
function assemble_hess(a          :: Gridap.FESpaces.GenericSparseMatrixAssembler,
                       cell_r_yu  :: T,
                       cell_id_yu :: Gridap.Arrays.IdentityVector{Int64}) where T <: AbstractArray

  #Counts the nnz for the lower triangular.
  n = count_hess_nnz_coo(a, cell_r_yu, cell_id_yu)

  I, J, V = Gridap.FESpaces.allocate_coo_vectors(Gridap.FESpaces.get_matrix_type(a), n)

  #nini keeps track of the number of assignements
  nini = fill_hess_coo_numeric!(I, J, V, a, cell_r_yu, cell_id_yu)

  @assert n == nini

  (I, J, V)
end

function count_hess_nnz_coo(a          :: Gridap.FESpaces.GenericSparseMatrixAssembler,
                            cell_r_yu  :: T,
                            cell_id_yu :: Gridap.Arrays.IdentityVector{Int64}) where T <: AbstractArray

  cellmat_rc  = cell_r_yu
  cellidsrows = cell_id_yu
  cellidscols = cell_id_yu

  cell_rows   = Gridap.FESpaces.get_cell_dofs(a.test, cellidsrows)
  cell_cols   = Gridap.FESpaces.get_cell_dofs(a.trial, cellidscols)
  rows_cache  = Gridap.FESpaces.array_cache(cell_rows)
  cols_cache  = Gridap.FESpaces.array_cache(cell_cols)
  cellmat_r   = Gridap.FESpaces.attach_constraints_cols(a.trial, cellmat_rc, cellidscols)
  cellmat     = Gridap.FESpaces.attach_constraints_rows(a.test,  cellmat_r,  cellidsrows)

  @assert length(cell_cols) == length(cell_rows)

  mat = first(cellmat)
  Is  = Gridap.FESpaces._get_block_layout(mat)
  n   = _count_hess_entries(a.matrix_type, rows_cache, cols_cache,
                            cell_rows, cell_cols, a.strategy, Is)

  n
end

@noinline function _count_hess_entries(::Type{M}, rows_cache, cols_cache,
                                       cell_rows, cell_cols, strategy, Is) where M
  n = 0
  for cell in 1:length(cell_cols)
    rows = getindex!(rows_cache, cell_rows, cell)
    cols = getindex!(cols_cache, cell_cols, cell)
    n += _count_hess_entries_at_cell(M, rows, cols, strategy, Is)
  end
  n
end

@inline function _count_hess_entries_at_cell(::Type{M}, rows, cols, strategy, Is) where M
  n = 0
  for gidcol in cols
    if gidcol > 0 &&  Gridap.FESpaces.col_mask(strategy, gidcol)
      _gidcol =  Gridap.FESpaces.col_map(strategy, gidcol)
      for gidrow in rows
        if gidrow > 0 &&  Gridap.FESpaces.row_mask(strategy, gidrow)
          _gidrow =  Gridap.FESpaces.row_map(strategy, gidrow)
          if Gridap.FESpaces.is_entry_stored(M, _gidrow, _gidcol) && (_gidrow >= _gidcol)
            n += 1
          end
        end
      end
    end
  end
  n
end

function fill_hess_coo_numeric!(I          :: Array{Ii,1},
                                J          :: Array{Ii,1},
                                V          :: Array{Vi,1},
                                a          :: Gridap.FESpaces.GenericSparseMatrixAssembler,
                                cell_r_yu  :: T,
                                cell_id_yu :: Gridap.Arrays.IdentityVector{Int64}) where {T <: AbstractArray, Ii <: Int, Vi <: AbstractFloat}
  nini = 0

  cellmat_rc  = cell_r_yu
  cellidsrows = cell_id_yu
  cellidscols = cell_id_yu

    cell_rows  = Gridap.FESpaces.get_cell_dofs(a.test,cellidsrows)
    cell_cols  = Gridap.FESpaces.get_cell_dofs(a.trial,cellidscols)
    cellmat_r  = Gridap.FESpaces.attach_constraints_cols(a.trial,cellmat_rc,cellidscols)
    cell_vals  = Gridap.FESpaces.attach_constraints_rows(a.test,cellmat_r,cellidsrows)
    rows_cache = Gridap.FESpaces.array_cache(cell_rows)
    cols_cache = Gridap.FESpaces.array_cache(cell_cols)
    vals_cache = Gridap.FESpaces.array_cache(cell_vals)
    nini = _fill_hess!(a.matrix_type, nini, I, J, V,
                                      rows_cache,cols_cache,vals_cache,
                                      cell_rows,cell_cols,cell_vals,
                                      a.strategy)

  nini
end

@noinline function _fill_hess!(a    :: Type{M},
                               nini :: Int,
                               I    :: Array{Ii,1},
                               J    :: Array{Ii,1},
                               V    :: Array{Vi,1},
                               rows_cache, cols_cache, vals_cache,
                               cell_rows,cell_cols,cell_vals,
                               strategy) where {M, Ii <: Int, Vi <: AbstractFloat}

  n = nini
  for cell in 1:length(cell_cols)
    rows = getindex!(rows_cache, cell_rows, cell)
    cols = getindex!(cols_cache, cell_cols, cell)
    vals = getindex!(vals_cache, cell_vals, cell)
    n = _fill_hess_at_cell!(M, n, I, J, V, rows, cols, vals, strategy)
  end
  n
end

"""
https://github.com/gridap/Gridap.jl/blob/758a8620756e164ba0e6b83dc8dcbb278015b3d9/src/FESpaces/SparseMatrixAssemblers.jl#L463
_fill_matrix_at_cell! may have a specific specialization
"""
@inline function _fill_hess_at_cell!(::Type{M},nini,
                                     I          :: Array{Ii,1},
                                     J          :: Array{Ii,1},
                                     V          :: Array{Vi,1},
                                     rows,cols,vals,strategy) where {M, Ii <: Int, Vi <: AbstractFloat}
  n = nini
  for (j, gidcol) in enumerate(cols)
    if gidcol > 0 && Gridap.FESpaces.col_mask(strategy, gidcol)
      _gidcol = Gridap.FESpaces.col_map(strategy, gidcol)
      for (i, gidrow) in enumerate(rows)
        if gidrow > 0 && Gridap.FESpaces.row_mask(strategy, gidrow)
          _gidrow = Gridap.FESpaces.row_map(strategy, gidrow)
          if Gridap.FESpaces.is_entry_stored(M, _gidrow, _gidcol) && (_gidrow >= _gidcol)
            n += 1
            @inbounds I[n] = _gidrow
            @inbounds J[n] = _gidcol
            @inbounds V[n] = vals[i,j]
          end
        end
      end
    end
  end
  n
end