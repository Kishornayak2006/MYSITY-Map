import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'admin_login_screen.dart';


enum MapType { normal, satellite, hybrid }

class UserMapScreen extends StatefulWidget {
  const UserMapScreen({super.key});

  @override
  State<UserMapScreen> createState() => _UserMapScreenState();
}

class _UserMapScreenState extends State<UserMapScreen> {
  final MapController mapController = MapController();
  final FlutterTts tts = FlutterTts();


  MapType currentMapType = MapType.normal;

  // LOCATION
  LatLng? myLocation;
  LatLng? destination;

  // ADMIN
  bool isAdminLoggedIn = false;
  LatLng? selectedHump;
  List<LatLng> humps = [];
  
  final Set<String> alertedHumps = {};



  // ROUTE
  List<LatLng> routePoints = [];
  List<String> turnInstructions = [];
  double? routeDistanceKm;

  // HUMP ALERT
  final double humpAlertDistance = 150;
  LatLng? activeHump;
  double? humpDistance;
  bool voiceSpoken = false;

  @override
  void initState() {
    super.initState();
    loadHumps();
    startLiveLocation();
    initTts();
  }

  // ================= VOICE =================
  Future<void> initTts() async {
    await tts.setLanguage('en-IN');
    await tts.setSpeechRate(0.45);
    await tts.setVolume(1.0);
  }

  Future<void> speak(String msg) async {
    await tts.stop();
    await tts.speak(msg);
  }

  // ================= LOCATION =================
  void startLiveLocation() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) return;

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen((pos) {
      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() => myLocation = latLng);
      mapController.move(latLng, 16);
      checkNearbyHumps(pos);
    });
  }

  // ================= HUMPS =================
  Future<void> loadHumps() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('humps');
    if (list != null) {
      humps = list.map((s) {
        final p = s.split(',');
        return LatLng(double.parse(p[0]), double.parse(p[1]));
      }).toList();
      setState(() {});
    }
  }

  Future<void> saveHumps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'humps',
      humps.map((h) => '${h.latitude},${h.longitude}').toList(),
    );
  }

  // ================= ROUTE =================
  Future<void> fetchRoute() async {
    if (myLocation == null || destination == null) return;

    final url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${myLocation!.longitude},${myLocation!.latitude};'
        '${destination!.longitude},${destination!.latitude}'
        '?overview=full&geometries=geojson&steps=true';

    final res = await http.get(Uri.parse(url));
    final data = json.decode(res.body);
    final route = data['routes'][0];

    setState(() {
      routePoints = (route['geometry']['coordinates'] as List)
          .map((c) => LatLng(c[1], c[0]))
          .toList();

      routeDistanceKm = route['distance'] / 1000;

      turnInstructions =
          (route['legs'][0]['steps'] as List).map<String>((s) {
        final m = s['maneuver'];
        final t = m['type'];
        final mod = m['modifier'] ?? '';
        if (t == 'turn') return 'Turn $mod';
        if (t == 'roundabout') return 'Enter roundabout';
        if (t == 'arrive') return 'You have arrived';
        return 'Continue straight';
      }).toList();

      activeHump = null;
      humpDistance = null;
      voiceSpoken = false;
    });
  }

  // ================= ROUTE–HUMP MATCH =================
  bool isHumpOnRoute(LatLng hump) {
    for (final p in routePoints) {
      final d = Geolocator.distanceBetween(
        p.latitude,
        p.longitude,
        hump.latitude,
        hump.longitude,
      );
      if (d <= 40) return true;
    }
    return false;
  }

  void checkNearbyHumps(Position pos) {
  final speedKmh = pos.speed * 3.6; // convert m/s to km/h

  double dynamicAlertDistance = 150;

  if (speedKmh > 50) {
    dynamicAlertDistance = 200;
  } else if (speedKmh > 30) {
    dynamicAlertDistance = 170;
  }

  for (final hump in humps) {
    final distance = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      hump.latitude,
      hump.longitude,
    );

    final key =
        '${hump.latitude.toStringAsFixed(6)},${hump.longitude.toStringAsFixed(6)}';

    if (distance <= dynamicAlertDistance &&
        !alertedHumps.contains(key)) {
      alertedHumps.add(key);
      showHumpAlert(distance);
    }

    if (distance > dynamicAlertDistance * 2) {
      alertedHumps.remove(key);
    }
  }
}

// 🚨 SHOW HUMP ALERT
void showHumpAlert(double distance) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.orange,
      content: Text(
        '⚠️ Hump ahead in ${distance.toStringAsFixed(0)} meters',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      duration: const Duration(seconds: 3),
    ),
  );
}


  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isAdminLoggedIn ? 'MYSITY MAP (ADMIN)' : 'MYSITY MAP'),
        backgroundColor: isAdminLoggedIn ? Colors.green : null,
        actions: [
          PopupMenuButton<MapType>(
            icon: const Icon(Icons.layers),
            onSelected: (v) => setState(() => currentMapType = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: MapType.normal, child: Text('Normal')),
              PopupMenuItem(value: MapType.satellite, child: Text('Satellite')),
              PopupMenuItem(value: MapType.hybrid, child: Text('Hybrid')),
            ],
          ),
          IconButton(
            icon: Icon(isAdminLoggedIn
                ? Icons.logout
                : Icons.admin_panel_settings),
            onPressed: () async {
              if (!isAdminLoggedIn) {
                final ok = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminLoginScreen()),
                );
                if (ok == true) setState(() => isAdminLoggedIn = true);
              } else {
                setState(() => isAdminLoggedIn = false);
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: const LatLng(12.2958, 76.6394),
              initialZoom: 14,
              onTap: (_, p) {
                if (isAdminLoggedIn) {
                  setState(() => selectedHump = p);
                } else {
                  setState(() => destination = p);
                  fetchRoute();
                }
              },
            ),
            children: [
              if (currentMapType == MapType.normal)
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                ),
              if (currentMapType != MapType.normal)
                TileLayer(
                  urlTemplate:
                      'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                ),
              if (currentMapType == MapType.hybrid)
                TileLayer(
                  urlTemplate:
                      'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                ),

              if (routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                        points: routePoints,
                        strokeWidth: 5,
                        color: Colors.blue),
                  ],
                ),

              MarkerLayer(
                markers: [
                  if (myLocation != null)
                    Marker(
                      point: myLocation!,
                      child:
                          const Icon(Icons.my_location, color: Colors.blue),
                    ),
                  if (destination != null)
                    Marker(
                      point: destination!,
                      child: const Icon(Icons.flag, color: Colors.red),
                    ),

                  // 🟠 HUMP ICON ON ROUTE
                  if (activeHump != null)
                    Marker(
                      point: activeHump!,
                      child: const Icon(Icons.warning,
                          color: Colors.orange, size: 30),
                    ),

                  if (isAdminLoggedIn)
                    ...humps.map(
                      (h) => Marker(
                        point: h,
                        child: GestureDetector(
                          onLongPress: () {
                            setState(() => humps.remove(h));
                            saveHumps();
                          },
                          child: const Icon(Icons.warning,
                              color: Colors.orange),
                        ),
                      ),
                    ),

                  if (selectedHump != null)
                    Marker(
                      point: selectedHump!,
                      child: const Icon(Icons.add_location_alt,
                          color: Colors.blue),
                    ),
                ],
              ),
            ],
          ),

          // DISTANCE
          if (routeDistanceKm != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Distance: ${routeDistanceKm!.toStringAsFixed(2)} km',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),

          // ⚠️ HUMP WARNING + COUNTDOWN
          if (activeHump != null && humpDistance != null)
            Positioned(
              top: 72,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.orange,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '⚠️ HUMP AHEAD in ${humpDistance!.toStringAsFixed(0)} m',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),

          // SAVE HUMP
          if (isAdminLoggedIn && selectedHump != null)
            Positioned(
              left: 16,
              bottom: 90,
              child: FloatingActionButton.extended(
                backgroundColor: Colors.orange,
                icon: const Icon(Icons.warning),
                label: const Text('Save Hump'),
                onPressed: () {
                  humps.add(selectedHump!);
                  selectedHump = null;
                  saveHumps();
                  setState(() {});
                },
              ),
            ),
        ],
      ),
    );
  }
}
