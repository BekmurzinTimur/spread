shader_type canvas_item;

// One burst per quad: shards thrown outward over a thin expanding ring.
// Custom data: birth time, base angle (negative: ring only), scale, quad half-extent.

uniform float now;
uniform float lifetime;
uniform float hold;
uniform int shards;
uniform float shard_distance;
uniform float shard_radius;
uniform float ring_start;
uniform float ring_end;
uniform float ring_width;
uniform float ring_alpha;

varying float k;
varying float angle;
varying float scale;
varying float extent;

void vertex() {
	float age = now - INSTANCE_CUSTOM.r;
	k = age / lifetime;
	angle = INSTANCE_CUSTOM.g;
	scale = INSTANCE_CUSTOM.b;
	extent = INSTANCE_CUSTOM.a;
	// Dead: zero-area quad, no fragments.
	if (age < 0.0 || age >= lifetime) {
		VERTEX = vec2(0.0);
	}
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * extent;
	float d = length(p);
	float ease = 1.0 - pow(1.0 - k, 2.0);

	// Negative angle: a lone ring, and scale is its final radius.
	bool ring_only = angle < 0.0;
	float ring_r = mix(ring_start, ring_only ? scale : ring_end * scale, ease);
	float half_w = ring_width * (1.0 - k) * 0.5;
	float aa = fwidth(d);
	float ring = ring_alpha * (1.0 - smoothstep(half_w - aa, half_w + aa, abs(d - ring_r)));

	float r = shard_radius * scale * (1.0 - k);
	float shard = 0.0;
	int shard_count = ring_only ? 0 : shards;
	for (int i = 0; i < shard_count; i++) {
		float a = angle + TAU * float(i) / float(shards);
		float speed = 0.75 + 0.35 * fract(float(i) * 0.618);
		vec2 c = vec2(cos(a), sin(a)) * shard_distance * scale * speed * ease;
		float sd = length(p - c);
		shard = max(shard, 1.0 - smoothstep(r * 0.85, r + aa, sd));
	}

	float alpha = shard + ring * (1.0 - shard);
	float fade = 1.0 - smoothstep(hold, 1.0, k);
	COLOR = vec4(COLOR.rgb, COLOR.a * alpha * fade);
}
