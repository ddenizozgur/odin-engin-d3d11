package r

import "core:math"
import "core:math/linalg"

//
// Color
//
RGBA8 :: distinct [4]byte

LIGHTGRAY :: RGBA8{200, 200, 200, 255}
GRAY :: RGBA8{130, 130, 130, 255}
DARKGRAY :: RGBA8{80, 80, 80, 255}
YELLOW :: RGBA8{253, 249, 0, 255}
GOLD :: RGBA8{255, 203, 0, 255}
ORANGE :: RGBA8{255, 161, 0, 255}
PINK :: RGBA8{255, 109, 194, 255}
RED :: RGBA8{230, 41, 55, 255}
MAROON :: RGBA8{190, 33, 55, 255}
GREEN :: RGBA8{0, 228, 48, 255}
LIME :: RGBA8{0, 158, 47, 255}
DARKGREEN :: RGBA8{0, 117, 44, 255}
SKYBLUE :: RGBA8{102, 191, 255, 255}
BLUE :: RGBA8{0, 121, 241, 255}
DARKBLUE :: RGBA8{0, 82, 172, 255}
PURPLE :: RGBA8{200, 122, 255, 255}
VIOLET :: RGBA8{135, 60, 190, 255}
DARKPURPLE :: RGBA8{112, 31, 126, 255}
BEIGE :: RGBA8{211, 176, 131, 255}
BROWN :: RGBA8{127, 106, 79, 255}
DARKBROWN :: RGBA8{76, 63, 47, 255}

WHITE :: RGBA8{255, 255, 255, 255}
BLACK :: RGBA8{0, 0, 0, 255}
BLANK :: RGBA8{0, 0, 0, 0}
MAGENTA :: RGBA8{255, 0, 255, 255}
RAYWHITE :: RGBA8{245, 245, 245, 255}

NAYSAYER_BG :: RGBA8{7, 38, 38, 255}

rgba8_to_vec4f32 :: #force_inline proc(c: RGBA8) -> [4]f32 {
	return cast([4]f32)c * (1.0 / 255.0)
}

vec4f32_to_rgba8 :: #force_inline proc(v: [4]f32) -> RGBA8 {
	c := linalg.clamp(v, 0.0, 1.0) * 255.0

	bytes := RGBA8 {
		cast(byte)math.round_f32(c.r),
		cast(byte)math.round_f32(c.g),
		cast(byte)math.round_f32(c.b),
		cast(byte)math.round_f32(c.a),
	}

	return bytes
}

//
//
//
Align_Kind :: enum {
	TopLeft,
	TopCenter,
	TopRight,
	CenterLeft,
	Center,
	CenterRight,
	BottomLeft,
	BottomCenter,
	BottomRight,
}

pos_from_align_kind :: proc(pos, size: [2]f32, kind: Align_Kind) -> [2]f32 {
	real_pos := pos

	switch kind {
	case .TopLeft:
	case .TopCenter:
		real_pos.x -= size.x * 0.5
	case .TopRight:
		real_pos.x -= size.x
	case .CenterLeft:
		real_pos.y -= size.y * 0.5
	case .Center:
		real_pos -= size * 0.5
	case .CenterRight:
		real_pos.x -= size.x
		real_pos.y -= size.y * 0.5
	case .BottomLeft:
		real_pos.y -= size.y
	case .BottomCenter:
		real_pos.x -= size.x * 0.5
		real_pos.y -= size.y
	case .BottomRight:
		real_pos -= size
	}

	return real_pos
}

point_within_rect :: proc(p: [2]f32, pos, size: [2]f32) -> bool {
	if p.x > pos.x && p.y > pos.y {
		br := pos + size
		if p.x < br.x && p.y < br.y {
			return true
		}
		return false
	}
	return false
}
