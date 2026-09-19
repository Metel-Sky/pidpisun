enum FileKind { directory, png, pdf, docx, other }

class FileSystemEntry {
  const FileSystemEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.kind,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final FileKind kind;
}

class PinnedFolder {
  const PinnedFolder({required this.name, required this.path});

  final String name;
  final String path;

  Map<String, dynamic> toJson() => {'name': name, 'path': path};

  factory PinnedFolder.fromJson(Map<String, dynamic> json) {
    return PinnedFolder(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
    );
  }
}

class StampPlacement {
  const StampPlacement({
    required this.id,
    required this.pageIndex,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.pngPath,
    required this.aspectRatio,
    this.opacity = 1,
    this.color,
    this.rotation = 0,
  });

  final String id;
  final int pageIndex;
  final double x;
  final double y;
  final double width;
  final double height;
  final String pngPath;
  final double aspectRatio;
  final double opacity;
  /// ARGB ink. `null` keeps the PNG's own color.
  final int? color;

  /// Clockwise degrees on the PDF only. The PNG file is never modified.
  final double rotation;

  static const pointsPerMm = 72.0 / 25.4;
  static const minSizePoints = 24.0;

  static double mmToPoints(double mm) => mm * pointsPerMm;

  static double pointsToMm(double points) => points / pointsPerMm;

  static String formatMm(double mm) {
    if ((mm - mm.roundToDouble()).abs() < 0.05) {
      return '${mm.round()}';
    }
    return mm.toStringAsFixed(1);
  }

  static double? parseMm(String raw) {
    final text = raw.trim().replaceAll(',', '.');
    if (text.isEmpty) {
      return null;
    }
    return double.tryParse(text);
  }

  static double normalizeRotation(double degrees) {
    var value = degrees % 360;
    if (value < 0) {
      value += 360;
    }
    return value;
  }

  StampPlacement copyWith({
    int? pageIndex,
    double? x,
    double? y,
    double? width,
    double? height,
    double? opacity,
    int? color,
    bool clearColor = false,
    double? rotation,
    String? pngPath,
  }) {
    return StampPlacement(
      id: id,
      pageIndex: pageIndex ?? this.pageIndex,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      pngPath: pngPath ?? this.pngPath,
      aspectRatio: aspectRatio,
      opacity: opacity ?? this.opacity,
      color: clearColor ? null : (color ?? this.color),
      rotation: rotation ?? this.rotation,
    );
  }

  Map<String, dynamic> toEngineJson() {
    final json = <String, dynamic>{
      'page': pageIndex,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'png': pngPath,
      'opacity': opacity,
      'rotate': rotation,
    };
    if (color != null) {
      final r = (color! >> 16) & 0xFF;
      final g = (color! >> 8) & 0xFF;
      final b = color! & 0xFF;
      String part(int value) => value.toRadixString(16).padLeft(2, '0');
      json['color'] = '#${part(r)}${part(g)}${part(b)}'.toUpperCase();
    }
    return json;
  }
}

class DocumentSession {
  const DocumentSession({
    required this.originalPath,
    required this.pdfPath,
    required this.convertedFromDocx,
    this.stamps = const [],
    this.selectedStampId,
    this.busyMessage,
  });

  final String originalPath;
  final String pdfPath;
  final bool convertedFromDocx;
  final List<StampPlacement> stamps;
  final String? selectedStampId;
  final String? busyMessage;

  DocumentSession copyWith({
    String? originalPath,
    String? pdfPath,
    bool? convertedFromDocx,
    List<StampPlacement>? stamps,
    String? selectedStampId,
    bool clearSelection = false,
    String? busyMessage,
    bool clearBusy = false,
  }) {
    return DocumentSession(
      originalPath: originalPath ?? this.originalPath,
      pdfPath: pdfPath ?? this.pdfPath,
      convertedFromDocx: convertedFromDocx ?? this.convertedFromDocx,
      stamps: stamps ?? this.stamps,
      selectedStampId: clearSelection
          ? null
          : (selectedStampId ?? this.selectedStampId),
      busyMessage: clearBusy ? null : (busyMessage ?? this.busyMessage),
    );
  }
}
