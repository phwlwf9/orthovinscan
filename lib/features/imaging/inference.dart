import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'imaging_service.dart';

enum InferenceAvailability { unavailable, notValidated, available }

/// Must accompany any future model integration; availability is not validation.
class InferenceModelManifest {
  const InferenceModelManifest({
    required this.id,
    required this.version,
    required this.license,
    required this.trainingDataProvenance,
    required this.evaluationReference,
    required this.intendedUse,
    required this.validatedForClinicalUse,
  });
  final String id;
  final String version;
  final String license;
  final String trainingDataProvenance;
  final String evaluationReference;
  final String intendedUse;
  final bool validatedForClinicalUse;
}

/// Coordinates are relative to the original input, in [0,1].
class FractureBoundingBox {
  const FractureBoundingBox(this.x, this.y, this.width, this.height);
  final double x, y, width, height;
}

class FractureInferenceResult {
  const FractureInferenceResult({
    required this.modelVersion,
    required this.region,
    required this.candidateCodes,
    required this.uncertaintyExplanation,
    required this.missingViewWarnings,
    this.boxes = const [],
    this.segmentationMask,
  });
  final String modelVersion;
  final String? region;
  final List<String> candidateCodes;
  final String uncertaintyExplanation;
  final List<String> missingViewWarnings;
  final List<FractureBoundingBox> boxes;
  final Uint8List? segmentationMask;
}

abstract interface class FractureInferenceService {
  InferenceAvailability get availability;
  InferenceModelManifest? get manifest;
  Future<FractureInferenceResult> analyze(
    PreparedRadiograph image, {
    required String view,
  });
}

/// Deliberately does not fabricate a result. No weights or model are bundled.
class UnavailableFractureInferenceService implements FractureInferenceService {
  const UnavailableFractureInferenceService();
  @override
  InferenceAvailability get availability => InferenceAvailability.unavailable;
  @override
  InferenceModelManifest? get manifest => null;
  @override
  Future<FractureInferenceResult> analyze(
    PreparedRadiograph image, {
    required String view,
  }) => Future.error(
    const ImagingException(
      'Chưa có mô hình AI đã được đánh giá. Sử dụng phân loại do bác sĩ hướng dẫn. '
      '/ No evaluated AI model is installed. Use clinician-guided classification.',
    ),
  );
}

class PreprocessedModelInput {
  const PreprocessedModelInput({
    required this.tensor,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.scale,
    required this.padX,
    required this.padY,
  });
  final Float32List tensor;
  final int width, height, sourceWidth, sourceHeight;
  final double scale;
  final int padX, padY;
}

/// Explicit, deterministic grayscale preprocessing for future ONNX/TFLite
/// adapters. A real adapter must match its own documented model input contract.
class ImagePreprocessing {
  static PreprocessedModelInput grayscaleLetterbox(
    PreparedRadiograph source, {
    int width = 512,
    int height = 512,
  }) {
    if (width < 1 || height < 1 || width > 4096 || height > 4096) {
      throw const ImagingException('Invalid model input size.');
    }
    final decoded = img.decodePng(source.pngBytes);
    if (decoded == null) throw const ImagingException('Invalid prepared PNG.');
    final scale = width / decoded.width < height / decoded.height
        ? width / decoded.width
        : height / decoded.height;
    final resizedWidth = (decoded.width * scale).round().clamp(1, width);
    final resizedHeight = (decoded.height * scale).round().clamp(1, height);
    final resized = img.copyResize(
      decoded,
      width: resizedWidth,
      height: resizedHeight,
      interpolation: img.Interpolation.linear,
    );
    final padX = (width - resizedWidth) ~/ 2;
    final padY = (height - resizedHeight) ~/ 2;
    final tensor = Float32List(width * height);
    for (final pixel in resized) {
      tensor[(pixel.y + padY) * width + pixel.x + padX] =
          (0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b) / 255;
    }
    return PreprocessedModelInput(
      tensor: tensor,
      width: width,
      height: height,
      sourceWidth: decoded.width,
      sourceHeight: decoded.height,
      scale: scale,
      padX: padX,
      padY: padY,
    );
  }
}
