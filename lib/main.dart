import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';

class GeofenceAlertApp extends StatefulWidget {
  @override
  _GeofenceAlertAppState createState() => _GeofenceAlertAppState();
}

class _GeofenceAlertAppState extends State<GeofenceAlertApp> {
  final FlutterLocalNotificationsPlugin _notification = FlutterLocalNotificationsPlugin();
  LatLng? _selectedLocation;
  double _geofenceRadius = 150.0; // Geofence radius in meters
  List<Marker> _markers = [];
  List<CircleMarker> _geofenceCircles = [];
  bool _isTracking = false;
  final ValueNotifier<bool> _isGeofenceActive = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _initNotifications();
  }

  Future<void> _initPermissions() async {
    final locationStatus = await Permission.location.request();
    final alwaysStatus = await Permission.locationAlways.request();
    final notificationStatus = await Permission.notification.request();

    if (locationStatus.isDenied ||
        alwaysStatus.isDenied ||
        notificationStatus.isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Permissions are required for geofencing!")),
      );
    }
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOSSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iOSSettings);

    await _notification.initialize(settings);

    const androidChannel = AndroidNotificationChannel(
      'geofence_alert',
      'Geofence Alerts',
      description: 'Notifications for geofence boundary crossings',
      importance: Importance.high,
    );

    await _notification
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> _sendNotification() async {
    const alarmDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'geofence_alert',
        'Geofence Alert',
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _notification.show(
      0,
      "Geofence Alert",
      "You have entered the geofence area.",
      alarmDetails,
    );

    if ((await Vibration.hasVibrator()) ?? false) {
      Vibration.vibrate(pattern: [500, 1000, 500, 2000]);
    }
  }

  void _startLocationTracking() {
    Geolocator.getPositionStream().listen((Position position) async {
      if (_selectedLocation != null) {
        double distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          _selectedLocation!.latitude,
          _selectedLocation!.longitude,
        );

        if (distance <= _geofenceRadius && !_isGeofenceActive.value) {
          _isGeofenceActive.value = true;
          await _sendNotification();
        } else if (distance > _geofenceRadius && _isGeofenceActive.value) {
          _isGeofenceActive.value = false; // Reset when exiting the geofence
        }
      }
    });
  }

  void _stopLocationTracking() {
    setState(() {
      _isTracking = false;
      _isGeofenceActive.value = false;
    });
  }

  void _onMapTap(LatLng location) {
    setState(() {
      _selectedLocation = location;
      _markers = [
        Marker(
          point: location,
          width: 40,
          height: 40,
          child: const Icon(
            Icons.location_on,
            color: Colors.red,
            size: 40,
          ),
        ),
      ];
      _updateGeofenceCircle();
    });
  }

  void _updateGeofenceCircle() {
    if (_selectedLocation != null) {
      _geofenceCircles = [
        CircleMarker(
          point: _selectedLocation!,
          radius: _geofenceRadius,
          color: Colors.blue.withOpacity(0.2),
          borderColor: Colors.blue,
          borderStrokeWidth: 2,
        ),
      ];
    }
  }

  void _adjustCircleRadius(double zoom) {
    if (_selectedLocation != null) {
      setState(() {
        double visualRadius = _geofenceRadius / (zoom * 100); // Adjust radius
        _geofenceCircles = [
          CircleMarker(
            point: _selectedLocation!,
            radius: visualRadius,
            color: Colors.blue.withOpacity(0.2),
            borderColor: Colors.blue,
            borderStrokeWidth: 2,
          ),
        ];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Geofence Alert App"),
          centerTitle: true,
        ),
        body: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(18.5602, 73.8031),
                initialZoom: 13.0,
                onTap: (tapPosition, latLng) {
                  _onMapTap(latLng);
                },
                onPositionChanged: (position, _) {
                  _adjustCircleRadius(position.zoom!);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  userAgentPackageName: 'com.example.app',
                ),
                MarkerLayer(markers: _markers),
                CircleLayer(circles: _geofenceCircles),
              ],
            ),
            Positioned(
              bottom: 80,
              left: 20,
              right: 20,
              child: ElevatedButton(
                onPressed: () {
                  if (_selectedLocation != null) {
                    setState(() {
                      _isTracking = !_isTracking;
                    });
                    if (_isTracking) {
                      _startLocationTracking();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Geofence set! Tracking started.")),
                      );
                    } else {
                      _stopLocationTracking();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Geofence tracking stopped.")),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please select a location on the map.")),
                    );
                  }
                },
                child: Text(_isTracking ? "Stop Geofence Tracking" : "Set Geofence & Start Tracking"),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: ValueListenableBuilder<bool>(
                valueListenable: _isGeofenceActive,
                builder: (context, isActive, _) {
                  return Chip(
                    label: Text(isActive ? "Inside Geofence" : "Outside Geofence"),
                    backgroundColor: isActive ? Colors.green : Colors.red,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() => runApp(GeofenceAlertApp());
