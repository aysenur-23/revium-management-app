/// Tek bir fuar kaydı (Google Sheet: Fuar Adı, Başlangıç Tarihi, Bitiş Tarihi, Şehir, Web Site)
class Fuar {
  final String? tarih; // başlangıç yyyy-MM-dd
  final String? bitisTarih; // bitiş yyyy-MM-dd
  final String yer;
  final String fuarAdi;
  final String? website;

  const Fuar({
    this.tarih,
    this.bitisTarih,
    required this.yer,
    required this.fuarAdi,
    this.website,
  });

  factory Fuar.fromJson(Map<String, dynamic> json) {
    return Fuar(
      tarih: json['tarih'] as String?,
      bitisTarih: json['bitisTarih'] as String?,
      yer: json['yer'] as String? ?? '',
      fuarAdi: json['fuarAdi'] as String? ?? '',
      website: json['website'] as String?,
    );
  }
}
