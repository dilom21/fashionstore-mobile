// Pruebas de la ETAPA 6 (prenda PNG) del CU26 - Vestidor virtual.
//
// Verifican SOLO la lógica nueva: geometría BASE del ancla, aplicación de
// VestidorConfig UNA sola vez y SIN multiplicadores locales adicionales
// (width = shoulderWidth * factorAncho, height = torsoHeight * factorAlto),
// límites de opacidad y las decisiones de "no renderizar". No tocan cámara,
// MediaPipe ni red.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/vestidor_virtual/models/pose_detection_result.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/models/pose_landmark.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/models/prenda_geometry.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/models/torso_anchor.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/models/vestidor_config_model.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/services/torso_anchor_service.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/widgets/torso_anchor_overlay.dart';

void main() {
  group('TorsoAnchorService - geometría BASE (sin factores)', () {
    test('calcula centro, hombros, alto y giro sin margen 1.15', () {
      final TorsoAnchor? ancla = const TorsoAnchorService().calcular(
        _pose(
          hombros: <double>[0.40, 0.30, 0.60, 0.30],
          caderas: <double>[0.42, 0.70, 0.58, 0.70],
        ),
      );

      expect(ancla, isNotNull);
      expect(ancla!.shoulderWidth, closeTo(0.20, 1e-9));
      expect(ancla.torsoHeight, closeTo(0.40, 1e-9));
      expect(ancla.centerX, closeTo(0.50, 1e-9));
      expect(ancla.centerY, closeTo(0.50, 1e-9));
      expect(ancla.rotationRadians, closeTo(0.0, 1e-9));
      expect(ancla.esValido, isTrue);
    });

    test('la rotación sigue la inclinación de la línea de hombros', () {
      final TorsoAnchor? ancla = const TorsoAnchorService().calcular(
        _pose(
          hombros: <double>[0.40, 0.30, 0.60, 0.40],
          caderas: <double>[0.42, 0.70, 0.58, 0.70],
        ),
      );

      expect(ancla!.rotationRadians, closeTo(math.atan2(0.10, 0.20), 1e-9));
    });

    test('devuelve null sin pose, sin un hombro o con hombros verticales', () {
      expect(const TorsoAnchorService().calcular(_poseSinPose()), isNull);

      expect(
        const TorsoAnchorService().calcular(
          _pose(
            hombros: <double>[0.40, 0.30],
            caderas: <double>[0.42, 0.70, 0.58, 0.70],
          ),
        ),
        isNull,
      );

      expect(
        const TorsoAnchorService().calcular(
          _pose(
            hombros: <double>[0.40, 0.20, 0.40, 0.60],
            caderas: <double>[0.42, 0.80, 0.58, 0.80],
          ),
        ),
        isNull,
      );
    });

    test('el margen 1.15 vive SOLO en el overlay de diagnóstico', () {
      expect(TorsoAnchorOverlay.factorAnchoDiagnosticoPorDefecto, 1.15);
      expect(TorsoAnchorOverlay.factorAltoDiagnosticoPorDefecto, 1.15);

      final TorsoAnchor ancla = const TorsoAnchorService().calcular(
        _pose(
          hombros: <double>[0.40, 0.30, 0.60, 0.30],
          caderas: <double>[0.42, 0.70, 0.58, 0.70],
        ),
      )!;
      // El ancla entrega el ancho REAL: el 1.15 se aplica al dibujar, no aquí.
      expect(ancla.shoulderWidth, closeTo(0.20, 1e-12));
    });
  });

  group('Orientación frente/espalda (regresión Etapa 6)', () {
    test('espaldas: hombros horizontales dan ancho 0.40 y rotación 0', () {
      final TorsoAnchor ancla = _anclaDe(
        hombroIzq: <double>[0.30, 0.40],
        hombroDer: <double>[0.70, 0.40],
      )!;

      expect(ancla.shoulderWidth, closeTo(0.40, 1e-9));
      expect(ancla.rotationRadians, closeTo(0.0, 1e-9));
      expect(ancla.torsoHeight, greaterThan(0));
    });

    test('frente: los mismos hombros con orden invertido dan lo mismo', () {
      final TorsoAnchor ancla = _anclaDe(
        hombroIzq: <double>[0.70, 0.40],
        hombroDer: <double>[0.30, 0.40],
      )!;

      expect(ancla.shoulderWidth, closeTo(0.40, 1e-9));
      // Sin normalizar, `atan2` devolvía ±π: el ancla se descartaba o giraba mal.
      expect(ancla.rotationRadians, closeTo(0.0, 1e-9));
      expect(ancla.rotationRadians.abs(), lessThan(math.pi / 2));
    });

    test('frente y espalda producen la MISMA geometría de prenda', () {
      final PrendaGeometry espalda = PrendaGeometry.desde(
        anchor: _anclaDe(
          hombroIzq: <double>[0.30, 0.40],
          hombroDer: <double>[0.70, 0.40],
        ),
        configuracion: _config(),
      )!;
      final PrendaGeometry frente = PrendaGeometry.desde(
        anchor: _anclaDe(
          hombroIzq: <double>[0.70, 0.40],
          hombroDer: <double>[0.30, 0.40],
        ),
        configuracion: _config(),
      )!;

      expect(frente.width, closeTo(espalda.width, 1e-9));
      expect(frente.height, closeTo(espalda.height, 1e-9));
      expect(frente.centerX, closeTo(espalda.centerX, 1e-9));
      expect(frente.centerY, closeTo(espalda.centerY, 1e-9));
      expect(frente.rotationRadians, closeTo(espalda.rotationRadians, 1e-9));
      // El factor sigue aplicándose UNA sola vez (nada de 1.15 por dentro).
      expect(frente.width, closeTo(0.40 * 1.35, 1e-9));
    });

    test('inclinación: el mismo gesto visual con orden invertido', () {
      final TorsoAnchor inclinado = _anclaDe(
        hombroIzq: <double>[0.30, 0.40],
        hombroDer: <double>[0.70, 0.50],
      )!;
      final TorsoAnchor invertido = _anclaDe(
        hombroIzq: <double>[0.70, 0.50],
        hombroDer: <double>[0.30, 0.40],
      )!;

      final double esperado = math.atan2(0.10, 0.40);
      expect(inclinado.rotationRadians, closeTo(esperado, 1e-9));
      expect(invertido.rotationRadians, closeTo(esperado, 1e-9));
      // La diferencia debe ser ~0 radianes, NO ~π.
      expect(
        (invertido.rotationRadians - inclinado.rotationRadians).abs(),
        lessThan(1e-9),
      );
    });

    test(
      'valores reales del teléfono (H11 0.52 / H12 0.23) son utilizables',
      () {
        final TorsoAnchor ancla = _anclaDe(
          hombroIzq: <double>[0.52, 0.40],
          hombroDer: <double>[0.23, 0.40],
        )!;

        expect(ancla.shoulderWidth, closeTo(0.29, 1e-9));
        expect(ancla.shoulderWidth, greaterThan(0));
        expect(ancla.torsoHeight, greaterThan(0));
        expect(ancla.rotationRadians, closeTo(0.0, 1e-9));
      },
    );
  });

  group('PrendaGeometry - VestidorConfig aplicado una sola vez', () {
    test('aplica factores, offsets, rotación y opacidad', () {
      final PrendaGeometry? prenda = PrendaGeometry.desde(
        anchor: _anclaBase(),
        configuracion: _config(
          factorAncho: 1.35,
          factorAlto: 1.55,
          offsetX: 0.02,
          offsetY: 0.05,
          rotacionOffset: 0.10,
          opacidad: 0.9,
        ),
      );

      expect(prenda, isNotNull);
      // 0.20 × 1.35 = 0.27 → NO hay doble escalado (no se multiplica por 1.15).
      expect(prenda!.width, closeTo(0.27, 1e-9));
      expect(prenda.height, closeTo(0.40 * 1.55, 1e-9));
      expect(prenda.centerX, closeTo(0.52, 1e-9));
      expect(prenda.centerY, closeTo(0.55, 1e-9));
      expect(prenda.rotationRadians, closeTo(0.10, 1e-9));
      expect(prenda.opacidad, closeTo(0.9, 1e-9));
      expect(prenda.esVisible, isTrue);
    });

    test('la opacidad se limita a 0..1', () {
      expect(PrendaGeometry.limitarOpacidad(1.7), 1.0);
      expect(PrendaGeometry.limitarOpacidad(-0.3), 0.0);
      expect(PrendaGeometry.limitarOpacidad(0.42), closeTo(0.42, 1e-9));
    });

    test('opacidad 0 no es visible', () {
      final PrendaGeometry? prenda = PrendaGeometry.desde(
        anchor: _anclaBase(),
        configuracion: _config(opacidad: 0),
      );
      expect(prenda, isNotNull);
      expect(prenda!.esVisible, isFalse);
    });

    test('sin ancla no hay prenda', () {
      expect(
        PrendaGeometry.desde(anchor: null, configuracion: _config()),
        isNull,
      );
    });

    test('configuración no usable no intenta renderizar', () {
      expect(
        PrendaGeometry.desde(
          anchor: _anclaBase(),
          configuracion: _config(assetUrl: '   '),
        ),
        isNull,
      );
      expect(
        PrendaGeometry.desde(
          anchor: _anclaBase(),
          configuracion: _config(tipoAsset: 'WEBP'),
        ),
        isNull,
      );
      expect(
        PrendaGeometry.desde(
          anchor: _anclaBase(),
          configuracion: _config(zonaCuerpo: 'PIERNAS'),
        ),
        isNull,
      );
    });

    test('ancla degenerada no genera prenda', () {
      const TorsoAnchor degenerada = TorsoAnchor(
        centerX: 0.5,
        centerY: 0.5,
        shoulderWidth: 0,
        torsoHeight: 0.4,
        rotationRadians: 0,
      );
      expect(
        PrendaGeometry.desde(anchor: degenerada, configuracion: _config()),
        isNull,
      );
    });
  });

  group('PrendaGeometry - aplicación directa de VestidorConfig', () {
    test('width y height salen SOLO del ancla y del backend', () {
      const TorsoAnchor doble = TorsoAnchor(
        centerX: 0.5,
        centerY: 0.5,
        shoulderWidth: 0.40,
        torsoHeight: 0.80,
        rotationRadians: 0.0,
      );
      final PrendaGeometry prenda = PrendaGeometry.desde(
        anchor: doble,
        configuracion: _config(),
      )!;

      // Sin multiplicadores locales: exactamente ancla × configuración.
      expect(prenda.width, closeTo(0.40 * 1.35, 1e-12));
      expect(prenda.height, closeTo(0.80 * 1.55, 1e-12));
    });

    test('la geometría es proporcional al tamaño del ancla', () {
      const TorsoAnchor doble = TorsoAnchor(
        centerX: 0.5,
        centerY: 0.5,
        shoulderWidth: 0.40,
        torsoHeight: 0.80,
        rotationRadians: 0.0,
      );
      final PrendaGeometry normal = PrendaGeometry.desde(
        anchor: _anclaBase(),
        configuracion: _config(),
      )!;
      final PrendaGeometry grande = PrendaGeometry.desde(
        anchor: doble,
        configuracion: _config(),
      )!;

      // El escalado dinámico (acercarse/alejarse) sigue intacto.
      expect(grande.width, closeTo(normal.width * 2, 1e-12));
      expect(grande.height, closeTo(normal.height * 2, 1e-12));
    });
  });
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

TorsoAnchor _anclaBase() => const TorsoAnchor(
  centerX: 0.5,
  centerY: 0.5,
  shoulderWidth: 0.20,
  torsoHeight: 0.40,
  rotationRadians: 0.0,
  hipWidth: 0.18,
);

VestidorConfig _config({
  String assetUrl = 'https://cdn.test/prenda.png',
  String tipoAsset = 'PNG_2D',
  String zonaCuerpo = 'TORSO',
  double factorAncho = 1.35,
  double factorAlto = 1.55,
  double offsetX = 0,
  double offsetY = 0,
  double rotacionOffset = 0,
  double opacidad = 1,
}) => VestidorConfig(
  configuracionId: 56,
  productoId: 6,
  assetUrl: assetUrl,
  zonaCuerpo: zonaCuerpo,
  tipoAsset: tipoAsset,
  factorAncho: factorAncho,
  factorAlto: factorAlto,
  offsetX: offsetX,
  offsetY: offsetY,
  rotacionOffset: rotacionOffset,
  ordenCapa: 1,
  opacidad: opacidad,
);

PoseDetectionResult _pose({
  required List<double> hombros,
  required List<double> caderas,
}) {
  final List<PoseLandmark> puntos = <PoseLandmark>[
    PoseLandmark(index: 11, x: hombros[0], y: hombros[1], z: 0),
    if (hombros.length >= 4)
      PoseLandmark(index: 12, x: hombros[2], y: hombros[3], z: 0),
    PoseLandmark(index: 23, x: caderas[0], y: caderas[1], z: 0),
    if (caderas.length >= 4)
      PoseLandmark(index: 24, x: caderas[2], y: caderas[3], z: 0),
  ];

  return PoseDetectionResult(
    poseDetected: true,
    timestampMs: 0,
    inferenceTimeMs: 0,
    landmarkCount: puntos.length,
    imageWidth: 640,
    imageHeight: 480,
    isFrontCamera: true,
    landmarks: puntos,
    worldLandmarks: const <PoseLandmark>[],
  );
}

PoseDetectionResult _poseSinPose() => const PoseDetectionResult(
  poseDetected: false,
  timestampMs: 0,
  inferenceTimeMs: 0,
  landmarkCount: 0,
  imageWidth: 640,
  imageHeight: 480,
  isFrontCamera: true,
  landmarks: <PoseLandmark>[],
  worldLandmarks: <PoseLandmark>[],
);

/// Ancla calculada con hombros explícitos y caderas simétricas por defecto.
TorsoAnchor? _anclaDe({
  required List<double> hombroIzq,
  required List<double> hombroDer,
  List<double>? caderaIzq,
  List<double>? caderaDer,
}) {
  return const TorsoAnchorService().calcular(
    _poseCon(
      hombroIzq: hombroIzq,
      hombroDer: hombroDer,
      caderaIzq: caderaIzq ?? <double>[0.35, 0.70],
      caderaDer: caderaDer ?? <double>[0.65, 0.70],
    ),
  );
}

/// Pose con los cuatro landmarks del torso en el orden recibido.
PoseDetectionResult _poseCon({
  required List<double> hombroIzq,
  required List<double> hombroDer,
  required List<double> caderaIzq,
  required List<double> caderaDer,
}) {
  final List<PoseLandmark> puntos = <PoseLandmark>[
    PoseLandmark(index: 11, x: hombroIzq[0], y: hombroIzq[1], z: 0),
    PoseLandmark(index: 12, x: hombroDer[0], y: hombroDer[1], z: 0),
    PoseLandmark(index: 23, x: caderaIzq[0], y: caderaIzq[1], z: 0),
    PoseLandmark(index: 24, x: caderaDer[0], y: caderaDer[1], z: 0),
  ];

  return PoseDetectionResult(
    poseDetected: true,
    timestampMs: 0,
    inferenceTimeMs: 0,
    landmarkCount: puntos.length,
    imageWidth: 640,
    imageHeight: 480,
    isFrontCamera: true,
    landmarks: puntos,
    worldLandmarks: const <PoseLandmark>[],
  );
}
