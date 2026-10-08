/// Motion types supported by the ShipdeHop Mascot presentation layer.
enum MascotMotion {
  none,
  idleFloat,
  hop,
  runMatching,
  bellWiggle,
  celebrateOnce,
  routeGlide,
  typingPulse,
}

class MascotMotionConfig {
  final MascotMotion motion;
  final Duration duration;
  final bool isLoop;

  const MascotMotionConfig({
    required this.motion,
    this.duration = const Duration(milliseconds: 600),
    this.isLoop = true,
  });

  static const MascotMotionConfig idle = MascotMotionConfig(
    motion: MascotMotion.idleFloat,
    duration: Duration(milliseconds: 3000),
    isLoop: true,
  );

  static const MascotMotionConfig hop = MascotMotionConfig(
    motion: MascotMotion.hop,
    duration: Duration(milliseconds: 550),
    isLoop: true,
  );

  static const MascotMotionConfig bell = MascotMotionConfig(
    motion: MascotMotion.bellWiggle,
    duration: Duration(milliseconds: 650),
    isLoop: false,
  );

  static const MascotMotionConfig celebrate = MascotMotionConfig(
    motion: MascotMotion.celebrateOnce,
    duration: Duration(milliseconds: 850),
    isLoop: false,
  );

  static const MascotMotionConfig typing = MascotMotionConfig(
    motion: MascotMotion.typingPulse,
    duration: Duration(milliseconds: 1200),
    isLoop: true,
  );
}
