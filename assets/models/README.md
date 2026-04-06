# Gender Model

Place your `gender_model.tflite` file here.

## Expected model spec
- Input:  [1, 64, 64, 3]  float32, normalized to [0.0, 1.0]
- Output: [1, 2]           float32, [male_probability, female_probability]

## Recommended source
You can use a pre-trained MobileNetV2 gender classifier fine-tuned on UTKFace or Adience dataset.
Convert to TFLite using TensorFlow's converter:

```python
converter = tf.lite.TFLiteConverter.from_saved_model('gender_model')
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_model = converter.convert()
open('gender_model.tflite', 'wb').write(tflite_model)
```

A ready-to-use model can be found at:
https://github.com/shubham0204/Age-Gender_Estimation_TF-Android
