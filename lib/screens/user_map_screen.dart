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

  // ADMIN & HUMPS
  bool isAdminLoggedIn = false;
  LatLng? selectedHump;
  List<LatLng> humps = [];
  final Set<String> alertedHumps = {};

  // ROUTE
  List<LatLng> routePoints = [];
  double? routeDistanceKm;

  // HUMP ALERT STATE
  LatLng? activeHump;
  double? humpDistance;

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
    await tts.setSpeechRate(0.5);
    await tts.setVolume(1.0);
  }

  Future<void> speak(String msg) async {
    await tts.stop();
    await tts.speak(msg);
  }

  // ================= LOCATION =================
  void startLiveLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() {
        myLocation = latLng;
      });
      // Move map smoothly with user
      mapController.move(latLng, mapController.camera.zoom);
      checkNearbyHumps(pos);
    });
  }

  // ================= HUMPS STORAGE =================
  Future<void> loadHumps() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('humps');
    if (list != null) {
      setState(() {
        humps = list.map((s) {
          final p = s.split(',');
          return LatLng(double.parse(p[0]), double.parse(p[1]));
        }).toList();
      });
    }
  }

  Future<void> saveHumps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'humps',
      humps.map((h) => '${h.latitude},${h.longitude}').toList(),
    );
  }

  // ================= ROUTING =================
  Future<void> fetchRoute() async {
    if (myLocation == null || destination == null) return;

    final url = 'https://router.project-osrm.org/route/v1/driving/'
        '${myLocation!.longitude},${myLocation!.latitude};'
        '${destination!.longitude},${destination!.latitude}'
        '?overview=full&geometries=geojson';

    try {
      final res = await http.get(Uri.parse(url));
      final data = json.decode(res.body);
      if (data['routes'] == null || data['routes'].isEmpty) return;

      final route = data['routes'][0];
      setState(() {
        routePoints = (route['geometry']['coordinates'] as List)
            .map((c) => LatLng(c[1], c[0]))
            .toList();
        routeDistanceKm = route['distance'] / 1000;
      });
    } catch (e) {
      debugPrint("Route error: $e");
    }
  }

  // ================= SMART HUMP ALERT =================
  void checkNearbyHumps(Position pos) {
    double speedKmh = pos.speed * 3.6;
    double dynamicAlertDistance = speedKmh > 50 ? 200 : 150;

    LatLng? nearestHump;
    double minDistance = double.infinity;

    for (final hump in humps) {
      final distance = Geolocator.distanceBetween(
        pos.latitude, pos.longitude,
        hump.latitude, hump.longitude,
      );

      final key = "${hump.latitude.toStringAsFixed(6)},${hump.longitude.toStringAsFixed(6)}";

      // Trigger Voice and Snack if entering alert zone
      if (distance <= dynamicAlertDistance && !alertedHumps.contains(key)) {
        alertedHumps.add(key);
        speak("Caution, speed breaker ahead");
        showHumpSnackBar(distance);
      }

      // Track the closest hump for the UI countdown
      if (distance <= dynamicAlertDistance && distance < minDistance) {
        minDistance = distance;
        nearestHump = hump;
      }

      // Reset alert for this hump if we have moved far away
      if (distance > dynamicAlertDistance * 2) {
        alertedHumps.remove(key);
      }
    }

    setState(() {
      activeHump = nearestHump;
      humpDistance = nearestHump != null ? minDistance : null;
    });
  }

  void showHumpSnackBar(double distance) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.deepOrange,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white),
            const SizedBox(width: 10),
            Text('Hump ahead: ${distance.toStringAsFixed(0)}m'),
          ],
        ),
      ),
    );
  }

  // ================= UI BUILD =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isAdminLoggedIn ? 'MYSITY MAP (Admin Mode)' : 'MYsity Map'),
        centerTitle: true,
        backgroundColor: isAdminLoggedIn ? Colors.green[700] : Colors.amber[700],
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<MapType>(
            icon: const Icon(Icons.layers),
            onSelected: (v) => setState(() => currentMapType = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: MapType.normal, child: Text('Normal Map')),
              const PopupMenuItem(value: MapType.satellite, child: Text('Satellite')),
              const PopupMenuItem(value: MapType.hybrid, child: Text('Hybrid')),
            ],
          ),
          IconButton(
            icon: Icon(isAdminLoggedIn ? Icons.logout : Icons.admin_panel_settings),
            onPressed: () async {
              if (!isAdminLoggedIn) {
                final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminLoginScreen()));
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
              initialCenter: const LatLng(12.2958, 76.6394), // Mysore
              initialZoom: 15,
              onTap: (_, p) {
                if (isAdminLoggedIn) {
                  setState(() => selectedHump = p);
                } else {
                  setState(() {
                    destination = p;
                    routePoints = []; // Clear old route
                  });
                  fetchRoute();
                }
              },
            ),
            children: [
              // TILE LAYERS
              if (currentMapType == MapType.normal)
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                )
              else
                TileLayer(
                  urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                ),
              if (currentMapType == MapType.hybrid)
                TileLayer(
                  urlTemplate: 'https://stamen-tiles.a.ssl.fastly.net/terrain-labels/{z}/{x}/{y}.jpg',
                ),

              // ROUTE LAYER
              if (routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(points: routePoints, strokeWidth: 6, color: Colors.blueAccent),
                  ],
                ),

              // MARKERS LAYER
              MarkerLayer(
                markers: [
                  if (myLocation != null)
                    Marker(
                      point: myLocation!,
                      width: 40, height: 40,
                      child: const Icon(Icons.navigation, color: Colors.blue, size: 30),
                    ),
                  if (destination != null)
                    Marker(
                      point: destination!,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                    ),
                  
                  // SHOW ALL HUMPS
                  ...humps.map((h) => Marker(
                    point: h,
                    child: GestureDetector(
                      onLongPress: () {
                        if (isAdminLoggedIn) {
                          setState(() => humps.remove(h));
                          saveHumps();
                        }
                      },
                      child: const Icon(Icons.warning_amber_rounded, color: Color.fromARGB(255, 25, 0, 255), size: 25),
                    ),
                  )),

                  if (selectedHump != null)
                    Marker(
                      point: selectedHump!,
                      child: const Icon(Icons.add_location_alt, color: Colors.green, size: 35),
                    ),
                ],
              ),
            ],
          ),

          // TOP INFO CARD (Distance)
          if (routeDistanceKm != null)
            Positioned(
              top: 10, left: 15, right: 15,
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    '🏁 Distance to destination: ${routeDistanceKm!.toStringAsFixed(2)} km',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ),

          // HUMP COUNTDOWN OVERLAY
          if (humpDistance != null)
            Positioned(
              bottom: 120, left: 50, right: 50,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '⚠️ Speed Breaker in ${humpDistance!.toStringAsFixed(0)}m',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),

          // ADMIN SAVE BUTTON
          if (isAdminLoggedIn && selectedHump != null)
            Positioned(
              bottom: 20, left: 20,
              child: FloatingActionButton.extended(
                backgroundColor: Colors.green,
                onPressed: () {
                  setState(() {
                    humps.add(selectedHump!);
                    selectedHump = null;
                  });
                  saveHumps();
                },
                label: const Text("Confirm Hump"),
                icon: const Icon(Icons.check),
              ),
            ),

          // RE-CENTER BUTTON
          Positioned(
            bottom: 20, right: 20,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              onPressed: () {
                if (myLocation != null) mapController.move(myLocation!, 17);
              },
              child: const Icon(Icons.my_location, color: Colors.blue),
            ),
          ),
        ],
      ),
    );
  }
}