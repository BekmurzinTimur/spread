shader_type canvas_item;

// One orb or trail per quad, written once at birth and moved from its birth tick.
// Custom data: birth tick, slide x, slide y (quad units), lead in ticks.

uniform float sim_time;
uniform float hop_ticks;
uniform bool trail;
uniform float trail_length;

void vertex() {
	float age = sim_time - INSTANCE_CUSTOM.r;
	if (age < 0.0 || age >= hop_ticks) {
		// Landed or not yet born: zero-area quad.
		VERTEX = vec2(0.0);
	} else {
		float t = clamp((age + INSTANCE_CUSTOM.a) / hop_ticks, 0.0, 1.0);
		if (trail) {
			// Local x runs along the hop: stretch from tail to head.
			VERTEX.x = mix(max(0.0, t - trail_length), t, VERTEX.x + 0.5);
		} else {
			VERTEX += INSTANCE_CUSTOM.gb * t;
		}
	}
}
