String formatRemainingStorageUsage({
  required double usedGb,
  required double totalGb,
  String gbUnit = 'G',
  String mbUnit = 'M',
  String separator = '/',
}) {
  final safeTotalGb = totalGb < 0 ? 0.0 : totalGb;
  final remainingGb = (safeTotalGb - usedGb).clamp(0.0, safeTotalGb).toDouble();

  return '${_formatStorageAmount(remainingGb, gbUnit, mbUnit)}'
      '$separator'
      '${_formatStorageAmount(safeTotalGb, gbUnit, mbUnit)}';
}

String _formatStorageAmount(double gb, String gbUnit, String mbUnit) {
  if (gb < 1) {
    return '${(gb * 1024).toStringAsFixed(0)}$mbUnit';
  }

  return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)}$gbUnit';
}
