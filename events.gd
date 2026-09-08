class_name GameEvents

## Timeline card classification.
##
## The scripted EVENTS list that used to live here is gone.  It fired pre-written cards at fixed
## years, populations and colony counts — a second, parallel history running alongside the one
## the simulation was actually producing, and narrating things the player had not done.
##
## Every card on the timeline is now emergent: raised by Game._announce() because something
## genuinely happened — a colony founded, a famine, a first contact, a strike inbound, a swarm
## milestone crossed.  This palette classifies those cards; nothing here schedules anything.
##
## Copy is written in the instrument voice (see VOICE.md): factual, neutral, no editorialising.
## The text states what happened and the measured result; the player supplies any meaning.

## Category palette — used for notification card borders.
const CATEGORY_COLORS: Dictionary = {
	"civilization": Color(0.85, 0.55, 0.10),
	"science":      Color(0.20, 0.60, 0.90),
	"technology":   Color(0.20, 0.80, 0.40),
	"space":        Color(0.65, 0.30, 0.90),
	"warning":      Color(0.90, 0.20, 0.20),
}
