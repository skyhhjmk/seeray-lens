class CustomReportFormula {
  const CustomReportFormula({
    required this.name,
    required this.leftMetric,
    required this.operator,
    required this.rightMetric,
    required this.format,
  });

  static const metrics = <String>[
    'sessions',
    'unique_visitors',
    'page_views',
    'events',
    'bounced_sessions',
    'average_duration_ms',
    'bounce_rate',
  ];

  static const operators = <String>['add', 'subtract', 'multiply', 'divide'];

  static const formats = <String>['number', 'percent'];

  final String name;
  final String leftMetric;
  final String operator;
  final String rightMetric;
  final String format;

  factory CustomReportFormula.fromJson(Map<String, dynamic> json) =>
      CustomReportFormula(
        name: json['name'] as String? ?? '',
        leftMetric: json['leftMetric'] as String? ?? 'page_views',
        operator: json['operator'] as String? ?? 'divide',
        rightMetric: json['rightMetric'] as String? ?? 'sessions',
        format: json['format'] as String? ?? 'number',
      );

  Map<String, Object> toJson() => {
    'name': name,
    'leftMetric': leftMetric,
    'operator': operator,
    'rightMetric': rightMetric,
    'format': format,
  };

  @override
  bool operator ==(Object other) =>
      other is CustomReportFormula &&
      other.name == name &&
      other.leftMetric == leftMetric &&
      other.operator == operator &&
      other.rightMetric == rightMetric &&
      other.format == format;

  @override
  int get hashCode =>
      Object.hash(name, leftMetric, operator, rightMetric, format);
}
