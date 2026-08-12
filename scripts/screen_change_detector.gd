extends RefCounted
class_name PetScreenChangeDetector

const SAMPLE_WIDTH := 48
const SAMPLE_HEIGHT := 27
const PIXEL_CHANGE_THRESHOLD := 24

var _previous_sample := PackedByteArray()


func reset() -> void:
	_previous_sample.clear()


func has_baseline() -> bool:
	return not _previous_sample.is_empty()


func evaluate(image: Image) -> Dictionary:
	var sample := make_sample(image)
	if sample.is_empty():
		return {"valid": false, "score": 0.0, "changed_ratio": 0.0, "has_baseline": has_baseline()}
	if _previous_sample.is_empty() or _previous_sample.size() != sample.size():
		_previous_sample = sample
		return {"valid": true, "score": 0.0, "changed_ratio": 0.0, "has_baseline": false}

	var difference_sum := 0.0
	var changed_pixels := 0
	for index in sample.size():
		var difference := absi(int(sample[index]) - int(_previous_sample[index]))
		difference_sum += difference
		if difference >= PIXEL_CHANGE_THRESHOLD:
			changed_pixels += 1
	_previous_sample = sample
	return {
		"valid": true,
		"score": difference_sum / (float(sample.size()) * 255.0),
		"changed_ratio": float(changed_pixels) / float(sample.size()),
		"has_baseline": true
	}


func make_sample(image: Image) -> PackedByteArray:
	if not image or image.is_empty():
		return PackedByteArray()
	var reduced := image.duplicate() as Image
	reduced.resize(SAMPLE_WIDTH, SAMPLE_HEIGHT, Image.INTERPOLATE_BILINEAR)
	var sample := PackedByteArray()
	sample.resize(SAMPLE_WIDTH * SAMPLE_HEIGHT)
	var write_index := 0
	for y in SAMPLE_HEIGHT:
		for x in SAMPLE_WIDTH:
			sample[write_index] = clampi(roundi(reduced.get_pixel(x, y).get_luminance() * 255.0), 0, 255)
			write_index += 1
	return sample
