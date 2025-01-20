@vs vs
layout(binding = 0) uniform vs_params {
	mat4 mvp;
};

in vec3 position;
in vec3 normal;

out vec3 outNormal;

void main() {
	gl_Position = mvp * vec4(position, 1.0);
	outNormal = normal;
}
@end

@fs fs
in vec3 outNormal;
out vec4 frag_color;

void main() {
	if (outNormal.x != 0) {
		frag_color = vec4(0.6, 0.6, 0.6, 1.0);
	} else if (outNormal.z != 0) {
		frag_color = vec4(0.7, 0.7, 0.7, 1.0);
	} else {
		frag_color = vec4(0.9, 0.9, 0.9, 1.0);
	}
}
@end

@program cube vs fs
