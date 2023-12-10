"""
    pataki(m, n = 0)

Return the upper bound of [B02; Proposition 13.1], [P12; Corollary 3.3.1(1)]
for the minimal rank of an optimal solution for an SDP of `m` constraints.

!!! note
    The argument `n` is ignore and is there for the sole purpose of allowing
    the function to be used as `maxrank` optimizer attribute.

It is the maximal `r` such that `div(r * (r + 1), 2) ≤ m`.

!!! note
    This bound can trivially be improved by computing `min(pataki(m, n), n)`.
    This `min` with `n` is not done so that these two bounds can easily be
    manipulated independently. This allows doing `min(pataki(m, n) + 1, n)`.

[B02] Barvinok, "A Course in Convexity", 2002.
[P12] Pataki, "The geometry of semidefinite programming", 2012.
"""
function pataki(m, n = 0)
    r = MOI.Utilities.side_dimension_for_vectorized_dimension(m)
    if m < MOI.dimension(MOI.PositiveSemidefiniteConeTriangle(r))
        r -= 1
    end
    return r
end

"""
    barvinok(m, n)

Return the improved upper bound of [B02; Proposition 13.4]
for the minimal rank of an optimal solution for an SDP of `m` constraints.

[B02; Proposition 13.4] states that if `div(r * (r + 1), 2) ≤ m` and `1 < r < n`
then there exists a solution of rank `≤ r - 1`.
So for this case, `barvinok(m, n)` returns `r - 1` while `pataki(m, n)`
returns `r`.

!!! note
    This bound can trivially be improved by computing `min(barvinok(m, n), n)`.
    This `min` with `n` is not done so that these two bounds can easily be
    manipulated independently. This allows doing `min(barvinok(m, n) + 1, n)`.

[B02] Barvinok, "A Course in Convexity", 2002.
"""
function barvinok(m, n)
    r = pataki(m, n)
    if m == MOI.dimension(MOI.PositiveSemidefiniteConeTriangle(r)) && 1 < r < n
        r -= 1
    end
    return r
end

"""
    default_maxrank(m, n)

Return the value of `min(pataki(m + 1) + 1, n)` following the results of [BM05]
suggesting to use a `r > r_{m + 1}` where `r_{m}` is `pataki(m)`. So it means
`r > pataki(m + 1)` or equivalently `r ≥ pataki(m + 1) + 1`.

> "It is interesting to note that the implementation of Burer and Monteiro [BM03]
> required only `r ≥ r_m`, but now with the insight provided by Theorem 3.4, our
> implementation in Section 6 implements r ≥ r_{m+1}." [BM05; p. 433]

Although Theorem 3.4 requires `≥` [BM05; Theorem 5.3], the perturbed Augmented
Lagrangian implemented in SDPLR requires the strict version `>` [BM05; Theorem 5.3].

!!! note
    For `m > 1` `min(barvinok(m, n) + 1, n)` is the same as `min(pataki(m - 1, n) + 1, n)`.
    Without the `min(⋅ + 1, n)`, these can be different.  For instance, with
    `m = 3, n = 2`, `barvinok(3, 2) = 2` and `pataki(2, 2) = 1` but after passing
    them through `min(⋅ + 1, n)`, they are both `2`. The constraint `m > 1` is also
    important. For instance, with `m = 1` and `n = 2`, `SDPLR.barvinok(1, 2)` is `1` while
    `SDPLR.pataki(0, 2)` is `0`.

!!! note
    When calling the SDPLR executable, it defaults to choosing
    `min(isqrt(2m) + 1, n)` (see line 307 in the `getstorage` function in
    `SDPLR-1.03-beta/source/main.c`). The value of `isqrt(2m)` is equal to
    `MOI.Utilities.side_dimension_for_vectorized_dimension(m)`. The value
    is equal to `pataki(m + 1)` for all `m` between `1` and `17` except for `8` and `13`.
    However, starting from `18`, they are equal only around 50% of the times
    but the error is at most one since `isqrt(2m) - 1 ≤ pataki(m + 1) ≤ isqrt(2m)`
    always holds. The value `isqrt(2m)` is therefore always larger so it goes in
    the direction of a more benign landscape which is a safe choice.

[BM03] Burer, Samuel, and Monteiro, Renato DC.
"A nonlinear programming algorithm for solving semidefinite programs via low-rank factorization."
Mathematical programming 95.2 (2003): 329-357.
[BM05] Burer, Samuel, and Monteiro, Renato DC.
"Local minima and convergence in low-rank semidefinite programming."
Mathematical programming 103.3 (2005): 427-444.
"""
default_maxrank(m, n) = min(isqrt(2m) + 1, n)
