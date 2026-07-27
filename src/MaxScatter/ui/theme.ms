/*  MaxScatter -- theme constants

    Native Max look with a single cyan accent. MAXScript rollout buttons expose
    no colour property, so the accent lands where the API actually allows it:
    the checkbutton highlight, the hyperlink, and the holder wire colour.
*/

global MaxScatter

struct MaxScatter_Theme
(
    accent      = (color 60 190 210),
    accentHover = (color 130 225 245),
    winWidth    = 340,
    winHeight   = 560
)

MaxScatter.theme = MaxScatter_Theme()
