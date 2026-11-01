shader_type spatial;

// A planet's surface map, free of the artefacts an equirectangular map picks up at the poles.
//
// 1. Mesh streaks.  A SphereMesh has a fan of triangles at each pole whose vertices all sit on
//    the pole itself but carry different u coordinates, so each triangle smears one slice of the
//    map into a wedge and the pole shows a star of streaks.  Here the map coordinates are not
//    interpolated from the vertices at all: each fragment works out its own longitude and
//    latitude from its direction from the planet's centre, using the same layout SphereMesh
//    generates (u = atan(x, z) / TAU, v = acos(y) / PI), so the map lands exactly where it did
//    and is continuous right up to the pole.
//
// 2. Texel noise.  Each row of texels is stretched around a full circle of latitude, so near a
//    pole many texels crowd into a ring a few pixels across and shimmer.  Towards the poles each
//    sample is averaged over about `blur_texels` of ground distance — along the circle of
//    latitude, where the crowding is, that span covers the texels squeezed into it and no more —
//    fading in from `blur_start_deg` of latitude and untouched below it.
//
// Otherwise a plain lit surface, matching the StandardMaterial3D it replaces (see planet.gd).
// Also used for textured moons.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
// Latitude, in degrees, where the smoothing begins; it reaches full strength at the poles.
uniform float blur_start_deg : hint_range(0.0, 90.0) = 70.0;
// Width of the averaging, in texels of ground distance (texel widths at the equator).
uniform float blur_texels : hint_range(0.0, 16.0) = 2.0;
// Faint self-light, as a fraction of the surface colour, so a small body stays readable on its
// night side (the moons use it; the planets leave it at 0).
uniform float self_light : hint_range(0.0, 1.0) = 0.0;

// ── A world being taken apart ────────────────────────────────────────────────
//
// Past the crust there is no surface left to show: hot silicate, then iron.  Rather than swap in
// another map — there is none to swap in, and a flat colour would read as a billiard ball — the
// surface map stays in play as the body's STRUCTURE.  Its own light and dark modulate the
// exposed material, so a half-eaten Mars still reads as Mars with its crust off: the maria and
// the highlands are still there, as brighter and darker exposed rock.
//
// Driven from disassembly.gd's look(), off one excavation depth.  All zero on an untouched
// world, which is every world in a run that never does this.
uniform float strip_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec4 strip_color : source_color = vec4(1.0);
uniform float strip_glow : hint_range(0.0, 1.0) = 0.0;
uniform float strip_metallic : hint_range(0.0, 1.0) = 0.0;

const int TAPS_U = 8;
const int TAPS_V = 3;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;          // object space, so the map turns with the planet
}

void fragment() {
	vec3 n = normalize(local_pos);
	// Longitude is undefined exactly on the axis; any value will do there.
	float theta = length(n.xz) > 1e-6 ? atan(n.x, n.z) / TAU : 0.0;   // -0.5 .. 0.5
	vec2 uv = vec2(fract(theta), acos(clamp(n.y, -1.0, 1.0)) / PI);

	// Screen-space derivatives for mip selection.  u jumps from 1 back to 0 at the map's seam,
	// which would read as an enormous derivative and draw a blurred line down it, so u is also
	// measured with the jump moved to the far side of the planet and the smaller of the two
	// derivatives is kept.
	float ua = fract(theta);
	float ub = theta;                                        // seam at ±0.5 instead of 0/1
	vec2 dx = vec2(abs(dFdx(ua)) < abs(dFdx(ub)) ? dFdx(ua) : dFdx(ub), dFdx(uv.y));
	vec2 dy = vec2(abs(dFdy(ua)) < abs(dFdy(ub)) ? dFdy(ua) : dFdy(ub), dFdy(uv.y));

	vec4 tex;
	float lat = abs(0.5 - uv.y) * PI;                        // 0 at the equator, PI/2 at a pole
	float w = smoothstep(radians(blur_start_deg), PI * 0.5, lat);
	if (w <= 0.0) {
		tex = textureGrad(albedo_tex, uv, dx, dy);
	} else {
		// Radii in UV.  Along latitude the ring shrinks as cos(lat), so the same ground distance
		// is a wider span of u — capped at the whole ring (±0.5).
		vec2 size = vec2(textureSize(albedo_tex, 0));
		float ru = min(0.5, w * blur_texels / size.x / max(cos(lat), 1e-3));
		float rv = w * blur_texels / size.y;
		// Read from the mip level whose texels are about as wide as the gap between taps, so the
		// taps average the texels between them instead of skipping over them — but never a
		// sharper level than the pixel's own footprint calls for.  The footprint is measured in
		// ground distance: along latitude u races round the ring near a pole, and taken at face
		// value that would pick an ever blurrier level until the pole itself read the map's
		// single-texel average.  The crowding along latitude is the taps' job.
		vec2 gap = vec2(2.0 * ru / float(TAPS_U - 1), 2.0 * rv / float(TAPS_V - 1)) * size;
		vec2 ground = size * vec2(cos(lat), 1.0);
		float footprint = max(length(dx * ground), length(dy * ground));
		float lod = log2(max(max(max(gap.x, gap.y), footprint), 1.0));
		vec4 sum = vec4(0.0);
		float wsum = 0.0;
		for (int j = 0; j < TAPS_V; j++) {
			float tv = float(j) / float(TAPS_V - 1) * 2.0 - 1.0;
			float v = clamp(uv.y + tv * rv, 0.0, 1.0);
			for (int i = 0; i < TAPS_U; i++) {
				float tu = float(i) / float(TAPS_U - 1) * 2.0 - 1.0;
				float k = exp(-2.0 * (tu * tu + tv * tv));    // gaussian falloff
				sum += textureLod(albedo_tex, vec2(uv.x + tu * ru, v), lod) * k;
				wsum += k;
			}
		}
		tex = sum / wsum;
	}
	vec3 surf = albedo_color.rgb * tex.rgb;
	if (strip_mix <= 0.0) {
		ALBEDO = surf;
		EMISSION = ALBEDO * self_light;
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
	} else {
		// The map's luminance, re-centred on 1.0, is the only thing carried across: it keeps the
		// body's features as variation in the exposed material instead of discarding them.
		// Clamped well away from zero so a dark sea does not become a black hole in the mantle.
		float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
		float relief = clamp(0.55 + 0.9 * lum, 0.35, 1.6);
		vec3 exposed = strip_color.rgb * relief;
		ALBEDO = mix(surf, exposed, strip_mix);
		// Incandescence follows the relief too, so the low ground glows hottest — which is where
		// an excavation would actually have reached.
		float heat = strip_glow * strip_mix * clamp(1.5 - lum, 0.2, 1.5);
		EMISSION = ALBEDO * max(self_light, heat);
		// Exposed rock is rough; exposed iron is not.
		ROUGHNESS = mix(1.0, 0.35, strip_metallic * strip_mix);
		METALLIC = strip_metallic * strip_mix;
	}
}
