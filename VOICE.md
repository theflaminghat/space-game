# Don't Go Extinct — Voice & Tone Guide

The horror in this game comes from **cosmic indifference** and **the scale of the
infinite** — discovered by the player, never narrated to them. The text's only job
is to report facts accurately and get out of the way. Every dread the player feels
is a conclusion *they* reached. If a line reaches for that conclusion, it has failed.

## The one principle

**The game is an instrument. It reports; it does not narrate, dramatise, or
editorialise.** Read every line as if it were a sensor readout, a log entry, or an
encyclopedia abstract. The tone for founding a colony and for losing a
billion-year civilisation is identical. That uniformity is the indifference.

## The register

- Observational and impersonal. State what is, what happened, what the instruments show.
- Technical precision. Real units, real magnitudes, named mechanisms.
- Calm and flat. No escalation of tone for "important" events.
- Complete but minimal. End where a report ends, not where a story would.

## Do

1. **State facts and magnitudes; let scale do the work.** `Mean orbital radius:
   1.07 AU` lands harder than "the swollen, dying sun." The number is the horror.
2. **Prefer numbers to adjectives.** If a word only adds mood, cut it. If it carries
   information (a quantity, a mechanism, a result), keep it.
3. **Name the mechanism, not the feeling.** "UV flux exceeds habitable tolerance,"
   not "searing radiation floods the system."
4. **Withhold the conclusion.** Report the condition and stop. Never tell the player
   what it means or how to feel. `Inhabited worlds: 0` — not "humanity is gone."
5. **Keep one register across all eras.** 1945 and heat death share the same flat
   voice. Human history read as log entries is part of the effect.
6. **Let juxtaposition be the only lever.** You may *place* facts beside each other
   (the run's age next to the universe's; the same notification card for a colony's
   founding and its destruction) — but never *comment* on the placement.

## Don't

1. **No dread/grandeur adjectives.** Banned by default: brilliant, searing, doomed,
   fragile, silent void, inevitable, ashes, cradle, consumed, ravaged, desperate,
   unimaginable, brink.
2. **No editorial conclusions.** Not "it made no difference," "nothing remains," "all
   was lost." State what remains, numerically.
3. **No second-person emotional address.** Not "you feel," "your heart," "you must."
   The instrument doesn't know your feelings or your obligations.
4. **No narrator omniscience or foreshadowing.** The instrument knows the present and
   the data. It does not know "what comes next" except as a projection with a number.
5. **No exclamation, no rhetorical questions, no portent.** ("And so it begins.")
6. **Don't rank events by tone.** Copy must never signal "this one matters more."

## Before / after (real game copy)

**Event — the Sun leaves the main sequence**
- ✗ "Astronomers confirm the Sun has entered its red giant phase. Within a million
  years the inner planets will be consumed. Humanity must look to the stars."
- ✓ "Spectroscopy confirms Sol has left the main sequence. Projected envelope
  expansion reaches 1.0 AU in ~1,000,000 years."

**Asteroid impact**
- ✗ "A mountain-sized asteroid has slammed into Earth. The strike and its aftermath
  have flattened every structure on the world and killed billions. The survivors
  must rebuild from the ruins."
- ✓ "Impact event recorded on Earth. Surface structures: 0 remaining.
  Population change: −2.1 billion (−68%)."

**Extinction — solar envelope expansion**
- ✗ "The expanding Sun has engulfed Mars. Every world humanity called home has been
  consumed by stellar fire."
- ✓ "Sol's photosphere now encloses the orbit of Mars. Inhabited worlds outside the
  photosphere: 0."

**Extinction — planetary nebula**
- ✗ "The dying Sun has shed its outer envelope in a brilliant planetary nebula,
  flooding the solar system with searing ultraviolet radiation. The remaining
  colonies have been sterilised."
- ✓ "Sol has ejected its outer envelope. System-wide UV flux exceeds habitable
  tolerance. Inhabited worlds: 0. Remnant: white dwarf, cooling."

**Colony established**
- ✗ "A permanent off-world colony has been established. For the first time in history,
  humanity's survival is no longer tied to a single world."
- ✓ "Permanent settlement recorded on Mars. Inhabited worlds: 2."

## Surface-by-surface

- **Notifications / timeline:** one or two sentences, log-entry voice. Same format and
  colour weight regardless of magnitude. State event, then measured result.
- **Research descriptions:** encyclopedia abstracts. The deep-future entries (proton
  decay, heat death) state the cosmology plainly — the dread is in the fact, not the
  phrasing. The player chose to read it.
- **Extinction / run-end screen:** a readout, not a eulogy. Cause stated as a measured
  condition. Stats as numbers, optionally beside a cosmic reference value. No closing
  line of commentary.

  ```
  CIVILISATION RECORD
  Endured            4,200,000,000 years
  Person-years       1.7×10^19
  Peak population    9.4×10^11
  Worlds settled     6
  Final era          Stellar
  Cause              Solar envelope expansion
  ──
  Projected time to heat death   ~10^100 years
  ```
- **Buildings / recipes:** spec-sheet voice (already largely correct). Function,
  inputs, outputs, real-world basis.
- **Labels / tooltips:** terse, unit-bearing. No mood.

## Litmus test (apply to every line before it ships)

> Could this be a sensor readout, a log entry, or an encyclopedia abstract?

If it sounds like a narrator, remove the affect. If a word carries a fact, keep it;
if it only carries mood, delete it. The reader should be able to feel horror in a
line that, on its face, is doing nothing but stating a number.
