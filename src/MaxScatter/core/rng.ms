/*  MaxScatter -- deterministic randomness

    Thin wrapper over MAXScript's generator so every draw in the package goes
    through one place. Reproducibility comes from reseeding before a run and
    keeping the draw order stable -- change the order of draws and the same
    seed yields a different layout.
*/

global MaxScatter

struct MaxScatter_RNG
(
    fn reseed s = ( seed (s as integer); ok ),
    fn unit = ( random 0.0 1.0 ),
    fn uniform lo hi = ( if lo == hi then lo else random lo hi )
)

MaxScatter.rng = MaxScatter_RNG()
