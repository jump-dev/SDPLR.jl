"""
    pataki(m)

Return the upper bound of [B02; Proposition 13.1], [P12; Corollary 3.3.1(1)]
for the minimal rank of an optimal solution for an SDP of `m` constraints.

It is the maximal `r` such that `div(r * (r + 1), 2) ≤ m`.

[B02] Barvinok, "A Course in Convexity", 2002.
[P12] Pataki, "The geometry of semidefinite programming", 2012.
"""
function pataki(m, n)
    r = MOI.Utilities.side_dimension_for_vectorized_dimension(m)
    if m < MOI.dimension(MOI.PositiveSemidefiniteConeTriangle(r))
        r -= 1
    end
    return min(n, r)
end

"""
    barvinok(m, n)

Return the improved upper bound of [B02; Proposition 13.4]
for the minimal rank of an optimal solution for an SDP of `m` constraints.

[B02; Proposition 13.4] states that if `div(r * (r + 1), 2) ≤ m` and `1 < r < n`
then there exists a solution of rank `≤ r - 1`.
So for this case, `barvinok(m, n)` returns `r - 1` while `pataki(m, n)`
returns `r`.

[B02] Barvinok, "A Course in Convexity", 2002.
"""
function barvinok(m, n = 0)
    r = pataki(m, n)
    if m == MOI.dimension(MOI.PositiveSemidefiniteConeTriangle(r)) && 1 < r < n
        r -= 1
    end
    return r
end

# See `getstorage` in `main.c`
default_maxrank(m, n) = min(isqrt(2m) + 1, n)
