/// Место для погоды: найденный или выбранный город.
class WeatherPlace {
  const WeatherPlace({required this.name, required this.lat, required this.lon, this.region});

  final String name;
  final String? region;
  final double lat;
  final double lon;

  Map<String, Object> toJson() => {'name': name, 'lat': lat, 'lon': lon};

  static WeatherPlace? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'], lat = raw['lat'], lon = raw['lon'];
    if (name is! String || lat is! num || lon is! num) return null;
    return WeatherPlace(name: name, lat: lat.toDouble(), lon: lon.toDouble());
  }
}
