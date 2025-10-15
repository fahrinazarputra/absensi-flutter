// lib/home_page.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart';

// Enumerasi untuk mengelola status tab
enum TabState { absensi, riwayat }

// Model Data untuk Riwayat Absensi
class AbsensiRecord {
  final String date;
  final String timeIn;
  final String timeOut;
  final String locationIn;
  final String locationOut;
  final String addressIn;
  final String addressOut;

  AbsensiRecord({
    required this.date,
    required this.timeIn,
    this.timeOut = 'Belum Absen',
    required this.locationIn,
    this.locationOut = 'N/A',
    required this.addressIn,
    this.addressOut = 'N/A',
  });

  AbsensiRecord copyWith({
    String? timeOut,
    String? locationOut,
    String? addressOut,
  }) {
    return AbsensiRecord(
      date: date,
      timeIn: timeIn,
      locationIn: locationIn,
      addressIn: addressIn,
      timeOut: timeOut ?? this.timeOut,
      locationOut: locationOut ?? this.locationOut,
      addressOut: addressOut ?? this.addressOut,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // --- USER DATA ---
  String userName = "";

  // --- KONSTANTA VALIDASI LOKASI ---
  static const double _maxValidAccuracyMeters = 500.0;
  static const double _targetLatitude = -7.181156; // bjn
  static const double _targetLongitude = 111.908777; // bjn
  static const double _maxDistanceMeters = 3000.0;

  // --- STATE ---
  TabState _activeTab = TabState.absensi;
  bool _isInValidArea = false;
  bool _isLocationAvailable = false;
  bool _isGpsReliable = false;
  bool _isClockedIn = false;
  bool _isProcessing = false;

  String _currentTime = '--:--';
  String _currentDate = '';
  String _locationStatus = 'Memuat lokasi...';
  String _currentAddress = 'Mencari nama jalan...';

  double _latitude = 0.0;
  double _longitude = 0.0;
  double _accuracy = 0.0;

  AbsensiRecord? _currentRecord;
  List<AbsensiRecord> _history = [];

  Timer? _locationTimer;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _updateTime();
    _startLocationTimer();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateTime(),
    );
  }

  @override
  void dispose() {
    _stopLocationTimer();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      userName = prefs.getString("name") ?? "User";
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("isLoggedIn", false);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  void _startLocationTimer() {
    _locationTimer?.cancel();
    _getLocation();
    _locationTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _getLocation(),
    );
  }

  void _stopLocationTimer() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  void _updateTime() {
    try {
      final now = DateTime.now();
      final timeFormat = DateFormat('HH:mm:ss');
      String formattedDate;
      try {
        formattedDate = DateFormat('EEEE, d MMMM y', 'id_ID').format(now);
      } catch (_) {
        // fallback kalau locale Indonesia belum diinisialisasi
        formattedDate = DateFormat('EEEE, d MMMM y', 'en_US').format(now);
      }
      if (!mounted) return;
      setState(() {
        _currentTime = timeFormat.format(now);
        _currentDate = formattedDate;
      });
    } catch (e) {
      // fallback hard-coded
      setState(() {
        _currentDate = DateTime.now().toIso8601String();
      });
    }
  }

  Future<String> _getAddressFromLatLng(double lat, double lon) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        return "${p.street ?? ''}, ${p.locality ?? ''}";
      }
      return 'Nama jalan tidak ditemukan';
    } catch (_) {
      return 'Gagal memuat alamat (Lat: ${lat.toStringAsFixed(4)}, Lon: ${lon.toStringAsFixed(4)})';
    }
  }

  bool _checkDistance(double lat, double lon) {
    double distanceInMeters = Geolocator.distanceBetween(
      lat,
      lon,
      _targetLatitude,
      _targetLongitude,
    );
    _isInValidArea = distanceInMeters <= _maxDistanceMeters;
    return _isInValidArea;
  }

  Future<void> _getLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationStatus = 'GPS tidak aktif.';
          _isLocationAvailable = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          setState(() {
            _locationStatus = 'Izin lokasi ditolak.';
            _isLocationAvailable = false;
          });
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final isReliable = pos.accuracy < _maxValidAccuracyMeters;
      final isInArea = _checkDistance(pos.latitude, pos.longitude);
      final address = await _getAddressFromLatLng(pos.latitude, pos.longitude);

      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _accuracy = pos.accuracy;
        _isGpsReliable = isReliable;
        _isLocationAvailable = true;
        _isInValidArea = isInArea;
        _currentAddress = address;
        _locationStatus = isReliable
            ? (isInArea
                  ? 'Lokasi akurat dan dalam area absensi'
                  : 'Di luar area absensi')
            : 'Akurasi GPS rendah (${pos.accuracy.toStringAsFixed(1)}m)';
      });
    } catch (e) {
      setState(() {
        _locationStatus = 'Gagal mengambil lokasi.';
        _isLocationAvailable = false;
      });
    }
  }

  Future<void> _handleAbsensi() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    await _getLocation();

    if (!_isGpsReliable || !_isInValidArea) {
      _showMessageBox(
        'Gagal Absen',
        'Pastikan GPS aktif dan berada di area yang diizinkan.',
        Colors.red,
      );
      setState(() => _isProcessing = false);
      return;
    }

    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);
    String dateStr;
    try {
      dateStr = DateFormat('EEEE, d MMMM y', 'id_ID').format(now);
    } catch (_) {
      dateStr = DateFormat('EEEE, d MMMM y', 'en_US').format(now);
    }

    if (!_isClockedIn) {
      _currentRecord = AbsensiRecord(
        date: dateStr,
        timeIn: timeStr,
        locationIn:
            'Lat: ${_latitude.toStringAsFixed(4)}, Lon: ${_longitude.toStringAsFixed(4)}',
        addressIn: _currentAddress,
      );
      _history.insert(0, _currentRecord!);
      _isClockedIn = true;
    } else {
      final updated = _currentRecord!.copyWith(
        timeOut: timeStr,
        locationOut:
            'Lat: ${_latitude.toStringAsFixed(4)}, Lon: ${_longitude.toStringAsFixed(4)}',
        addressOut: _currentAddress,
      );
      final idx = _history.indexOf(_currentRecord!);
      if (idx != -1) _history[idx] = updated;
      _isClockedIn = false;
      _currentRecord = null;
    }

    _showMessageBox(
      'Berhasil!',
      'Absensi berhasil dicatat.\nLokasi: $_currentAddress',
      Colors.green,
    );
    setState(() => _isProcessing = false);
  }

  void _showMessageBox(String title, String body, Color color) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Hi, $userName 👋"),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.white),
          ),
        ],
      ),
      body: _activeTab == TabState.absensi
          ? _buildAbsensiView()
          : _buildRiwayatView(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _activeTab.index,
        onTap: (i) {
          setState(() {
            _activeTab = TabState.values[i];
            if (_activeTab == TabState.absensi) {
              _startLocationTimer();
            } else {
              _stopLocationTimer();
            }
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.timer), label: "Absensi"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Riwayat"),
        ],
      ),
    );
  }

  Widget _buildAbsensiView() {
    final btnColor = _isClockedIn ? Colors.red : Colors.indigo;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_currentDate, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              _currentTime,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              _locationStatus,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isProcessing ? null : _handleAbsensi,
              style: ElevatedButton.styleFrom(
                backgroundColor: btnColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 50,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isClockedIn ? "Absen Pulang" : "Absen Masuk",
                      style: const TextStyle(fontSize: 18, color: Colors.white),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              _isLocationAvailable
                  ? "Koordinat: ${_latitude.toStringAsFixed(4)}, ${_longitude.toStringAsFixed(4)} (Acc ${_accuracy.toStringAsFixed(1)}m)"
                  : "Koordinat belum tersedia",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiwayatView() {
    if (_history.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Belum ada riwayat absensi.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _history.length,
      itemBuilder: (context, i) {
        final r = _history[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(r.date),
            subtitle: Text("Masuk: ${r.timeIn}\nPulang: ${r.timeOut}"),
            trailing: const Icon(Icons.location_on, color: Colors.orange),
          ),
        );
      },
    );
  }
}
