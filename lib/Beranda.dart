import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'Otentikasi.dart';
import 'Menelpon.dart';
import 'main.dart';

// Warna tema
const Color warnaUtama = Color(0xFF690909);
const Color warnaSekunder = Color(0xFF873A3A);
const Color warnaTeksHitam = Color(0xFF0F0F0F);

class LayarBeranda extends StatefulWidget {
  @override
  _LayarBerandaState createState() => _LayarBerandaState();
}

class _LayarBerandaState extends State<LayarBeranda> {
  final List<Map<String, dynamic>> daftarKontak = [];
  final List<Map<String, dynamic>> riwayatPanggilan = [];

  String? idPengguna;
  String? _idPanggilan;
  String? namaPengguna;
  String? avatarPengguna;
  String? statusPengguna;
  String idSaluran = ''; // Atur nilai awal default
  String idPemanggil = ''; // Atur nilai awal default

  Map<String, String> petaNamaPengguna = {}; // Menyimpan nama pengguna berdasarkan id

  @override
  void initState() {
    super.initState();
    setupFirebaseMessaging(context);
    _mintaIzin();
    _inisialisasiNotifikasiFCM();
    _ambilIdPengguna();
    _muatSemuaKontak();
  }

  Future<void> _mintaIzin() async {
    await [Permission.camera, Permission.microphone, Permission.notification, Permission.bluetooth].request();
  }

  Future<void> logoutPengguna(BuildContext context) async {
    try {
      // 1. Perbarui status pengguna di database (opsional)
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userId = user.uid;
        await FirebaseDatabase.instance
            .ref('pengguna/$userId')
            .update({'status': 'offline'});
      }

      // 2. Logout dari FirebaseAuth
      await FirebaseAuth.instance.signOut();

      // 3. Hapus data dari SharedPreferences
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // 4. Navigasikan pengguna ke layar login
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => LayarOtentikasi()),
      );
    } catch (e) {
      print("Kesalahan saat logout: $e");
    }
  }

  Future<void> _ambilIdPengguna() async {
    SharedPreferences preferensi = await SharedPreferences.getInstance();
    idPengguna = preferensi.getString('idPengguna');
    if (idPengguna != null) {
      _muatDataPengguna(idPengguna!);
      _muatKontak();
      _muatRiwayatPanggilan();
    }
  }

  void _muatSemuaKontak() {
    DatabaseReference referensiPengguna = FirebaseDatabase.instance.ref('pengguna');
    referensiPengguna.onValue.listen((DatabaseEvent event) {
      try {
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        setState(() {
          daftarKontak.clear();
          if (data != null) {
            data.forEach((id, nilai) {
              // Cek jika idPengguna sama dengan idPengguna saat ini, lewati
              if (id != idPengguna) {
                daftarKontak.add({
                  'idPengguna': id,
                  'namaPengguna': nilai['namaPengguna'] ?? 'Tidak diketahui',
                  'statusPengguna': nilai['statusPengguna'] ?? '',
                  'avatar': 'https://robohash.org/$id?set=set1', // Avatar menggunakan Robohash
                });
              }
            });
          }
        });
      } catch (error) {
        print("Error saat memuat semua kontak: $error");
      }
    });
  }

  void perbaruiStatusPanggilan(
      String idSaluran,
      String idPemanggil,
      String idPenerima, {
        required String status,
      }) {
    final DatabaseReference database = FirebaseDatabase.instance.ref();

    // Simpan riwayat panggilan pemanggil
    database.child("pengguna/$idPemanggil/riwayatPanggilan/$idSaluran").set({
      'idPenerima': idPenerima,
      'status': status,
      'waktu': DateTime.now().millisecondsSinceEpoch,
    });

    // Simpan riwayat panggilan penerima
    database.child("pengguna/$idPenerima/riwayatPanggilan/$idSaluran").set({
      'idPemanggil': idPemanggil,
      'status': status,
      'waktu': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void setupFirebaseMessaging(BuildContext context) {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Saat notifikasi diterima ketika aplikasi berjalan di foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("Pesan FCM diterima di foreground: ${message.data}");

      if (message.data['jenisPesan'] == 'panggilan') {
        tampilkanDialogPanggilan(
          context,
          idSaluran: message.data['idSaluran'] ?? '',
          idPemanggil: message.data['idPemanggil'] ?? '',
          idPenerima: message.data['idPenerima'] ?? '',
        );
      }
    });

    // Token untuk debug dan pengujian
    messaging.getToken().then((token) {
      print("FCM Token: $token");
      if (idPengguna != null) {
        _simpanTokenKeDatabase(token!);
      }
    });
  }

  void tampilkanDialogPanggilan(
      BuildContext context, {
        required String idSaluran,
        required String idPemanggil,
        required String idPenerima,
      }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text("Panggilan Masuk"),
          content: Text("Anda menerima panggilan dari $idPemanggil"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Tutup dialog
              },
              child: Text("Tolak"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Tutup dialog
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LayarMenelpon(
                      idPengguna: idPenerima,
                      idSaluran: idSaluran,
                      idPemanggil: idPemanggil,
                      idPenerima: idPenerima,
                      idPanggilan: idSaluran,
                      namaPengguna: '???', // Atur sesuai konteks
                    ),
                  ),
                );
              },
              child: Text("Terima"),
            ),
          ],
        );
      },
    );
  }

  void _simpanTokenKeDatabase(String token) {
    if (idPengguna != null) {
      DatabaseReference tokenRef = FirebaseDatabase.instance.ref('pengguna/$idPengguna');
      tokenRef.update({'fcmToken': token});
    }
  }

  void _inisialisasiNotifikasiFCM() async {
    FirebaseMessaging pesan = FirebaseMessaging.instance;

    // Periksa izin saat ini
    NotificationSettings pengaturan = await pesan.getNotificationSettings();

    if (pengaturan.authorizationStatus == AuthorizationStatus.notDetermined) {
      // Jika izin belum ditentukan, minta izin
      pengaturan = await pesan.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (pengaturan.authorizationStatus == AuthorizationStatus.denied) {
        print("Notifikasi ditolak oleh pengguna.");
        return;
      }
    } else if (pengaturan.authorizationStatus == AuthorizationStatus.denied) {
      print("Izin notifikasi sebelumnya ditolak oleh pengguna.");
      return;
    }

    // Mendapatkan token FCM untuk mengidentifikasi perangkat
    String? token = await pesan.getToken();
    if (token != null) {
      _simpanTokenKeDatabase(token);
    }

    // Mendengarkan notifikasi saat aplikasi sedang aktif
    FirebaseMessaging.onMessage.listen((RemoteMessage pesan) {
      if (pesan.notification != null) {
      }
    });
  }

  Future<String> _ambilNamaPengguna(String id) async {
    if (petaNamaPengguna.containsKey(id)) {
      return petaNamaPengguna[id]!;
    }
    DatabaseReference referensiPengguna = FirebaseDatabase.instance.ref('pengguna/$id');
    final snapshot = await referensiPengguna.get();
    if (snapshot.exists) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      String nama = data['namaPengguna'] ?? 'Tidak diketahui';
      petaNamaPengguna[id] = nama;
      return nama;
    }
    return 'Tidak diketahui';
  }

  void _muatDataPengguna(String idPengguna) {
    DatabaseReference referensiPengguna = FirebaseDatabase.instance.ref('pengguna/$idPengguna');
    referensiPengguna.onValue.listen((DatabaseEvent event) {
      try {
        final dataSnapshot = event.snapshot.value;
        if (dataSnapshot != null) {
          final data = Map<String, dynamic>.from(dataSnapshot as Map);
          setState(() {
            namaPengguna = data['namaPengguna'] ?? '';
            statusPengguna = data['statusPengguna'] ?? '';
          });
        }
      } catch (error) {
        print("Error saat memuat data pengguna: $error");
      }
    });
  }

  void _muatKontak() {
    DatabaseReference referensiKontak = FirebaseDatabase.instance.ref('pengguna/$idPengguna/kontak');
    referensiKontak.onValue.listen((DatabaseEvent event) {
      try {
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        setState(() {
          daftarKontak.clear();
          if (data != null) {
            data.forEach((key, value) {
              daftarKontak.add(value);
            });
          }
        });
      } catch (error) {
        print("Error saat memuat kontak: $error");
      }
    });
  }

  void _muatRiwayatPanggilan() {
    DatabaseReference referensiRiwayat = FirebaseDatabase.instance.ref('pengguna/$idPengguna/riwayatPanggilan');
    referensiRiwayat.onValue.listen((DatabaseEvent event) async {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      setState(() {
        riwayatPanggilan.clear();
        if (data != null) {
          data.forEach((key, value) async {
            final idPemanggil = value['idPemanggil'] ?? '';
            final idPenerima = value['idPenerima'] ?? '';
            final status = value['status'] ?? '';
            final waktu = value['waktu'] ?? 0;

            // Tentukan apakah pengguna ini adalah pemanggil atau penerima
            final isPemanggil = idPengguna == idPemanggil;
            final idLawanBicara = isPemanggil ? idPenerima : idPemanggil;

            // Ambil nama pengguna lawan bicara
            String namaLawanBicara = await _ambilNamaPengguna(idLawanBicara);

            // Tambahkan data riwayat dengan nama lawan bicara
            riwayatPanggilan.add({
              'idPemanggil': idPemanggil,
              'idPenerima': idPenerima,
              'status': status,
              'waktu': waktu,
              'namaLawanBicara': namaLawanBicara,
            });
          });
        }
      });
    });
  }

  void _lakukanPanggilanCepat() {
    TextEditingController pengontrolPanggilanCepat = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Membuat Panggilan Baru'),
          content: TextField(
            controller: pengontrolPanggilanCepat,
            decoration: InputDecoration(labelText: 'Masukkan ID Pengguna'),
          ),
          actions: [
            TextButton(
              child: Text('Batal', style: TextStyle(color: warnaUtama)),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: warnaUtama),
              child: Text('Panggil', style: TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.pop(context);
                _cariDanMulaiPanggilan(pengontrolPanggilanCepat.text);
              },
            ),
          ],
        );
      },
    );
  }

  void _cariDanMulaiPanggilan(String idPenerima) {
    DatabaseReference referensiPengguna = FirebaseDatabase.instance.ref('pengguna');
    referensiPengguna
        .orderByChild('idPengguna')
        .equalTo(idPenerima)
        .once()
        .then((DatabaseEvent event) {
      if (event.snapshot.exists) {
        _mulaiPanggilan(idPenerima);
      } else {
        _tampilkanDialogPenggunaTidakDitemukan(idPenerima);
      }
    });
  }

  void _tampilkanDialogPenggunaTidakDitemukan(String idPengguna) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Pengguna Tidak Ditemukan'),
          content: Text('Pengguna dengan ID $idPengguna tidak ditemukan.'),
          actions: [
            TextButton(
              child: Text('OK', style: TextStyle(color: warnaUtama)),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

  void _tampilkanKonfirmasiPanggilan(String namaPengguna, String idPengguna) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Menelpon $namaPengguna'),
          content: Text('Apakah anda ingin menelpon $namaPengguna?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Tutup dialog
              },
              child: Text('Batal', style: TextStyle(color: warnaUtama)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: warnaUtama),
              onPressed: () {
                Navigator.pop(context); // Tutup dialog
                _mulaiPanggilan(idPengguna); // Memulai panggilan
              },
              child: Text('Panggil', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _mulaiPanggilan(String idPenerima) async {
    // Buat idSaluran unik untuk setiap panggilan
    String idSaluran = "$idPengguna-$idPenerima";
    String idPemanggil = idPengguna!;
    String namaPenerima = await _ambilNamaPengguna(idPenerima);
    String waktuUnik = DateTime.now().millisecondsSinceEpoch.toString();
    _idPanggilan = waktuUnik; // Setel _idPanggilan di sini

    // Simpan riwayat panggilan untuk pemanggil
    final referensiRiwayatPemanggil = FirebaseDatabase.instance
        .ref('pengguna/$idPengguna/riwayatPanggilan/$_idPanggilan');

    referensiRiwayatPemanggil.set({
      'idPemanggil': idPengguna,
      'idPenerima': idPenerima,
      'status': 'Menghubungkan Panggilan',
      'waktu': DateTime.now().millisecondsSinceEpoch,
      'idSaluran': idSaluran,
    });

    // Simpan riwayat panggilan untuk penerima
    final referensiRiwayatPenerima = FirebaseDatabase.instance
        .ref('pengguna/$idPenerima/riwayatPanggilan/$_idPanggilan');

    referensiRiwayatPenerima.set({
      'idPemanggil': idPengguna,
      'idPenerima': idPenerima,
      'status': 'Menghubungkan Panggilan',
      'waktu': DateTime.now().millisecondsSinceEpoch,
      'idSaluran': idSaluran,
    });

    // Navigasi ke layar menelpon
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LayarMenelpon(
          idPengguna: idPengguna!,
          idSaluran: idSaluran,
          idPemanggil: idPemanggil,
          idPenerima: idPenerima,
          idPanggilan: _idPanggilan!,
          namaPengguna: namaPenerima,
          avatarPengguna: 'https://robohash.org/$idPenerima?set=set1',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: warnaUtama,
        leading: IconButton(
          icon: Icon(Icons.account_circle, color: Colors.white),
          onPressed: _tampilkanPengaturanProfil,
        ),
        title: Text(
          namaPengguna ?? 'Sedang memuat...',
          style: TextStyle(color: Colors.white, fontFamily: 'Poppins'),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              logoutPengguna(context);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daftar Pengguna',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
                color: warnaTeksHitam,
              ),
            ),
            SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: daftarKontak.isNotEmpty
                  ? ListView.builder(
                itemCount: daftarKontak.length,
                itemBuilder: (context, index) {
                  final kontak = daftarKontak[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: warnaSekunder,
                      backgroundImage: NetworkImage(kontak['avatar']),
                      radius: 20,
                    ),
                    title: FutureBuilder<String>(
                      future: _ambilNamaPengguna(kontak['idPengguna']),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Text('Memuat...');
                        } else if (snapshot.hasError) {
                          return Text('Error');
                        } else {
                          return Text(snapshot.data ?? 'Tidak Diketahui');
                        }
                      },
                    ),
                    subtitle: Text(
                      kontak['statusPengguna'],
                      style: TextStyle(
                        color: warnaTeksHitam.withOpacity(0.6),
                        fontFamily: 'Poppins',
                      ),
                    ),
                    onTap: () {
                      _tampilkanKonfirmasiPanggilan(kontak['namaPengguna'], kontak['idPengguna']);
                    },
                  );
                },
              )
                  : Center(
                child: Text(
                  'Tidak ada Pengguna ditemukan',
                  style: TextStyle(color: warnaTeksHitam.withOpacity(0.6)),
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Riwayat Panggilan',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
                color: warnaTeksHitam,
              ),
            ),
            SizedBox(height: 8),
            Expanded(
              flex: 3,
              child: riwayatPanggilan.isNotEmpty
                  ? ListView.builder(
                itemCount: riwayatPanggilan.length,
                itemBuilder: (context, index) {
                  final panggilan = riwayatPanggilan[index];
                  final namaLawanBicara = panggilan['namaLawanBicara'] ?? 'Tidak diketahui';
                  final status = panggilan['status'] ?? 'unknown';
                  final waktu = panggilan['waktu'] ?? 0;

                  final avatarUrl = 'https://robohash.org/${panggilan['idPemanggil']}?set=set1';

                  final waktuPanggilan = DateTime.fromMillisecondsSinceEpoch(waktu);
                  final waktuFormat = '${waktuPanggilan.hour.toString().padLeft(2, '0')}:${waktuPanggilan.minute.toString().padLeft(2, '0')}';

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: warnaSekunder,
                      backgroundImage: NetworkImage(avatarUrl),
                      radius: 20,
                    ),
                    title: Text(
                      namaLawanBicara,
                      style: TextStyle(
                        color: warnaTeksHitam,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '$status. $waktuFormat',
                      style: TextStyle(
                        color: warnaTeksHitam.withOpacity(0.6),
                        fontFamily: 'Poppins',
                      ),
                    ),
                    onTap: () {
                      // Tentukan lawan bicara berdasarkan konteks panggilan
                      final idLawanBicara = panggilan['idPemanggil'] == idPengguna
                          ? panggilan['idPenerima']
                          : panggilan['idPemanggil'];
                      final namaLawanBicara = panggilan['namaLawanBicara'] ?? 'Tidak diketahui';

                      // Tampilkan konfirmasi sebelum memulai panggilan
                      _tampilkanKonfirmasiPanggilan(namaLawanBicara, idLawanBicara);
                    },
                  );
                },
              )
                  : Center(
                child: Text(
                  'Tidak ada riwayat panggilan',
                  style: TextStyle(color: warnaTeksHitam.withOpacity(0.6)),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: warnaUtama,
        icon: Icon(Icons.add_call, color: Colors.white),
        label: Text(
          'Baru',
          style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
        ),
        onPressed: _lakukanPanggilanCepat,
      ),
    );
  }

  void _tampilkanPengaturanProfil() {
    TextEditingController namaController = TextEditingController(text: namaPengguna);
    TextEditingController statusController = TextEditingController(text: statusPengguna);

    final avatarUrl = 'https://robohash.org/$idPengguna?set=set1';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Pengaturan Profil'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundImage: NetworkImage(avatarUrl),
                backgroundColor: Colors.transparent,
              ),
              SizedBox(height: 10),
              Text(
                'ID Pengguna: $idPengguna',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              TextField(
                controller: namaController,
                decoration: InputDecoration(labelText: 'Nama Pengguna'),
                style: TextStyle(color: warnaUtama),
              ),
              TextField(
                controller: statusController,
                decoration: InputDecoration(labelText: 'Status'),
                style: TextStyle(color: warnaUtama),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text('Batal', style: TextStyle(color: warnaUtama)),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: warnaUtama),
              child: Text('Simpan', style: TextStyle(color: Colors.white)),
              onPressed: () {
                FirebaseDatabase.instance.ref('pengguna/$idPengguna').update({
                  'namaPengguna': namaController.text,
                  'statusPengguna': statusController.text,
                });
                setState(() {
                  namaPengguna = namaController.text;
                  statusPengguna = statusController.text;
                });
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }
}