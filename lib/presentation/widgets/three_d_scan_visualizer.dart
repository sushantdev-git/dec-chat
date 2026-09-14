import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

import '../theme/app_theme.dart';

/// Interactive 3D pulsating radar scan visualizer using three_js.
///
/// Renders a dynamic wireframe geodesic sphere (mesh nucleus), inner crystalline
/// core, dual counter-rotating orbital radar halos, and orbiting detected peer nodes.
/// Rhythmical sine pulsation simulates active BLE/Nostr spectrum radio pings.
///
/// Automatically provides a lightweight animated 2D radar fallback in headless
/// unit test environments where native OpenGL/ANGLE contexts are unavailable.
class ThreeDScanVisualizer extends StatefulWidget {
  final double height;
  final int peerCount;
  final VoidCallback? onStopScan;

  const ThreeDScanVisualizer({
    super.key,
    this.height = 210,
    this.peerCount = 0,
    this.onStopScan,
  });

  @override
  State<ThreeDScanVisualizer> createState() => _ThreeDScanVisualizerState();
}

class _ThreeDScanVisualizerState extends State<ThreeDScanVisualizer>
    with SingleTickerProviderStateMixin {
  three.ThreeJS? _threeJs;
  bool _hasError = false;
  double _animTime = 0.0;

  // Fallback 2D controller for headless test environments or during initial GL warm-up
  late final AnimationController _fallbackController;

  bool get _isHeadlessTest {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _fallbackController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isHeadlessTest && _threeJs == null && !_hasError) {
      final width = MediaQuery.of(context).size.width - 28;
      _initThreeJs(Size(width, widget.height));
    }
  }

  void _initThreeJs(Size size) {
    try {
      _threeJs = three.ThreeJS(
        settings: three.Settings(
          alpha: true,
          clearAlpha: 0.0,
          clearColor: 0x000000,
          antialias: true,
        ),
        size: size,
        loadingWidget: _build2DRadarFallback(),
        onSetupComplete: () {
          if (mounted) setState(() {});
        },
        setup: _setup3DScene,
      );
    } catch (e) {
      debugPrint('[ThreeDScanVisualizer] GL init fallback: $e');
      _hasError = true;
    }
  }

  Future<void> _setup3DScene() async {
    final threeJs = _threeJs;
    if (threeJs == null) return;

    // Aspect ratio & camera setup
    final aspect = threeJs.width / math.max(1.0, threeJs.height);
    threeJs.camera = three.PerspectiveCamera(45, aspect, 0.1, 100);
    threeJs.camera.position.setValues(0, 0, 7.2);

    threeJs.scene = three.Scene();

    final rootGroup = three.Group();
    threeJs.scene.add(rootGroup);

    // 1. Central Geodesic Wireframe Sphere (Mesh Network Core)
    final coreGeometry = three.IcosahedronGeometry(1.35, 1);
    final coreMaterial = three.MeshBasicMaterial.fromMap({
      'wireframe': true,
      'color': 0xFAFAFA,
      'transparent': true,
      'opacity': 0.85,
    });
    final coreMesh = three.Mesh(coreGeometry, coreMaterial);
    rootGroup.add(coreMesh);

    // 2. Inner Crystalline Nucleus (Cryptographic Seed)
    final nucleusGeometry = three.OctahedronGeometry(0.65, 0);
    final nucleusMaterial = three.MeshBasicMaterial.fromMap({
      'wireframe': true,
      'color': 0x71717A,
      'transparent': true,
      'opacity': 0.75,
    });
    final nucleusMesh = three.Mesh(nucleusGeometry, nucleusMaterial);
    rootGroup.add(nucleusMesh);

    // 3. Primary Orbital Radar Ring (Equatorial Tilt)
    final ring1Geometry = three.TorusGeometry(2.3, 0.022, 8, 48);
    final ring1Material = three.MeshBasicMaterial.fromMap({
      'wireframe': true,
      'color': 0xA1A1AA,
      'transparent': true,
      'opacity': 0.65,
    });
    final ring1Mesh = three.Mesh(ring1Geometry, ring1Material);
    ring1Mesh.rotation.x = math.pi / 2.5;
    rootGroup.add(ring1Mesh);

    // 4. Secondary Orbital Radar Ring (Polar Counter-Tilt)
    final ring2Geometry = three.TorusGeometry(2.7, 0.018, 8, 48);
    final ring2Material = three.MeshBasicMaterial.fromMap({
      'wireframe': true,
      'color': 0x52525B,
      'transparent': true,
      'opacity': 0.45,
    });
    final ring2Mesh = three.Mesh(ring2Geometry, ring2Material);
    ring2Mesh.rotation.y = math.pi / 3.0;
    rootGroup.add(ring2Mesh);

    // 5. Orbiting Peer Node Satellites (Simulating discovered mesh peers)
    final List<three.Mesh> satellites = [];
    final satGeometry = three.OctahedronGeometry(0.12, 0);
    final satMaterial = three.MeshBasicMaterial.fromMap({
      'wireframe': false,
      'color': 0xFFFFFF,
    });

    final satelliteConfigs = [
      [2.2, 0.4, 0.0],
      [-1.9, 1.1, -0.5],
      [0.6, -1.8, 0.9],
      [-2.4, -0.6, 0.4],
    ];

    for (final cfg in satelliteConfigs) {
      final satMesh = three.Mesh(satGeometry, satMaterial);
      satMesh.position.setValues(cfg[0], cfg[1], cfg[2]);
      rootGroup.add(satMesh);
      satellites.add(satMesh);
    }

    // Continuous 3D Animation Loop: Multi-axis rotation + Sine scale heartbeat
    threeJs.addAnimationEvent((double dt) {
      _animTime += dt;

      // Geodesic core rotation
      coreMesh.rotation.y += 0.75 * dt;
      coreMesh.rotation.x += 0.35 * dt;

      // Nucleus counter-rotation
      nucleusMesh.rotation.y -= 1.2 * dt;
      nucleusMesh.rotation.z += 0.6 * dt;

      // Orbital radar rings rotation
      ring1Mesh.rotation.z += 0.55 * dt;
      ring2Mesh.rotation.x += 0.3 * dt;
      ring2Mesh.rotation.y -= 0.45 * dt;

      // Rhythmic radar ping pulsation (sine wave heartbeat)
      final corePulse = 1.0 + 0.12 * math.sin(_animTime * 3.4);
      coreMesh.scale.setValues(corePulse, corePulse, corePulse);

      final nucleusPulse = 1.0 + 0.22 * math.cos(_animTime * 4.2);
      nucleusMesh.scale.setValues(nucleusPulse, nucleusPulse, nucleusPulse);

      final ringPulse = 1.0 + 0.05 * math.sin(_animTime * 2.0);
      ring1Mesh.scale.setValues(ringPulse, ringPulse, ringPulse);

      // Orbit satellites around mesh center
      for (int i = 0; i < satellites.length; i++) {
        final sat = satellites[i];
        final speed = 0.7 + i * 0.22;
        final angle = _animTime * speed + i * (math.pi * 2 / satellites.length);
        final radius = 2.1 + 0.35 * math.sin(_animTime * 1.5 + i);

        sat.position.x = radius * math.cos(angle);
        sat.position.z = radius * math.sin(angle);
        sat.position.y = 0.45 * math.sin(_animTime * 2.0 + i);
        sat.rotation.y += 2.0 * dt;
      }
    });
  }

  @override
  void dispose() {
    _fallbackController.dispose();
    _threeJs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: AppTheme.squircleLarge,
        border: Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.3), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryAccent.withValues(alpha: 0.05),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppTheme.squircleLarge,
        child: Stack(
          children: [
            // Background subtle radial radar glow
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.85,
                    colors: [
                      AppTheme.primaryAccent.withValues(alpha: 0.07),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // 3D ThreeJS Scene or Animated 2D Radar Fallback
            SizedBox(
              height: widget.height,
              width: double.infinity,
              child: (_isHeadlessTest || _hasError || _threeJs == null)
                  ? _build2DRadarFallback()
                  : _threeJs!.build(),
            ),

            // Top Telemetry Header
            Positioned(
              top: 12,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  // Pulsating live indicator dot
                  _buildLiveScanBadge(),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'RADIO DISCOVERY BURST',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  if (widget.onStopScan != null)
                    GestureDetector(
                      onTap: widget.onStopScan,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.darkCardElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.stop_rounded, size: 13, color: AppTheme.textSecondary),
                            SizedBox(width: 4),
                            Text(
                              'Stop',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Bottom Spectrum Status Bar
            Positioned(
              bottom: 12,
              left: 14,
              right: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sensors, size: 14, color: AppTheme.bleMeshBlue),
                      const SizedBox(width: 6),
                      Text(
                        'BLE 2.4 GHz + Nostr Relays',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentSubtle,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${widget.peerCount} ${widget.peerCount == 1 ? 'Peer' : 'Peers'} Found',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Live pulsating radar scan badge with glowing green dot
  Widget _buildLiveScanBadge() {
    return AnimatedBuilder(
      animation: _fallbackController,
      builder: (context, child) {
        final opacity = 0.4 + 0.6 * math.sin(_fallbackController.value * math.pi);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.verifiedGreen.withValues(alpha: opacity),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.verifiedGreen.withValues(alpha: opacity * 0.7),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'SCANNING',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: AppTheme.verifiedGreen,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 2D Pulsating Radar Sweep fallback for tests or when 3D context is absent
  Widget _build2DRadarFallback() {
    return AnimatedBuilder(
      animation: _fallbackController,
      builder: (context, child) {
        return CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _RadarFallbackPainter(progress: _fallbackController.value),
        );
      },
    );
  }
}

/// Custom painter rendering multi-tier expanding radar pulses and rotating sweep
class _RadarFallbackPainter extends CustomPainter {
  final double progress;

  _RadarFallbackPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) * 0.42;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 3 expanding concentric pulsating rings
    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress + i / 3.0) % 1.0;
      final radius = maxRadius * ringProgress;
      final alpha = (1.0 - ringProgress) * 0.45;
      ringPaint.color = AppTheme.primaryAccent.withValues(alpha: alpha);
      canvas.drawCircle(center, radius, ringPaint);
    }

    // Outer boundary static ring
    ringPaint.color = AppTheme.darkBorderSubtle;
    canvas.drawCircle(center, maxRadius, ringPaint);

    // Crosshairs
    final crossPaint = Paint()
      ..color = AppTheme.darkBorderSubtle.withValues(alpha: 0.6)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(center.dx - maxRadius, center.dy), Offset(center.dx + maxRadius, center.dy), crossPaint);
    canvas.drawLine(Offset(center.dx, center.dy - maxRadius), Offset(center.dx, center.dy + maxRadius), crossPaint);

    // Rotating radar sweep line
    final angle = progress * 2 * math.pi;
    final sweepEnd = Offset(
      center.dx + maxRadius * math.cos(angle),
      center.dy + maxRadius * math.sin(angle),
    );
    final sweepPaint = Paint()
      ..color = AppTheme.primaryAccent.withValues(alpha: 0.7)
      ..strokeWidth = 1.6;
    canvas.drawLine(center, sweepEnd, sweepPaint);

    // Center Core
    final corePaint = Paint()
      ..color = AppTheme.primaryAccent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 4, corePaint);
  }

  @override
  bool shouldRepaint(covariant _RadarFallbackPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
