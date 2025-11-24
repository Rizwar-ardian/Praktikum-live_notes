// ...existing code...
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart'; // otomatis dibuat oleh flutterfire configure


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Aktifkan persistence (opsional tapi membantu sinkronisasi dan loading)
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  runApp(const MyApp());
}
// ...existing code...
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Live Notes',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}
// ...existing code...
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Referensi koleksi Firestore
  final CollectionReference _notes =
      FirebaseFirestore.instance.collection('notes');

  // Controller input untuk tambah (tetap dipakai)
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  // Pagination / caching untuk mempercepat initial load
  final int _pageSize = 20;
  List<DocumentSnapshot> _items = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  StreamSubscription<QuerySnapshot>? _initialSub;

  @override
  void initState() {
    super.initState();
    _subscribeInitial();
  }

  @override
  void dispose() {
    _initialSub?.cancel();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _subscribeInitial() {
    final query = _notes.orderBy('timestamp', descending: true).limit(_pageSize);
    _initialSub = query.snapshots().listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        _items = snapshot.docs;
        _lastDoc = snapshot.docs.last;
        _hasMore = snapshot.docs.length == _pageSize;
      } else {
        _items = [];
        _lastDoc = null;
        _hasMore = false;
      }
      setState(() {});
    }, onError: (_) {
      // handle error jika perlu
    });
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore || _lastDoc == null) return;
    setState(() => _isLoadingMore = true);

    final nextQuery = _notes
        .orderBy('timestamp', descending: true)
        .startAfterDocument(_lastDoc!)
        .limit(_pageSize);

    final snap = await nextQuery.get();
    if (snap.docs.isNotEmpty) {
      _items.addAll(snap.docs);
      _lastDoc = snap.docs.last;
      _hasMore = snap.docs.length == _pageSize;
    } else {
      _hasMore = false;
    }

    setState(() => _isLoadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Live Notes Fire")),

      // Ganti StreamBuilder penuh dengan list paginasi yang cache data awal
      body: Builder(
        builder: (context) {
          if (_items.isEmpty) {
            // ketika belum ada data dari subscription
            return const Center(child: CircularProgressIndicator());
          }

          return ListView.builder(
            itemCount: _items.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _items.length) {
                // item footer: tombol muat lebih atau loading
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: _isLoadingMore
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: _loadMore, child: const Text('Muat lebih')),
                  ),
                );
              }

              final DocumentSnapshot document = _items[index];

              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  onTap: () => _showEditForm(document),
                  title: Text(
                    document['title'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(document['content'] ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      _notes.doc(document.id).delete();
                    },
                  ),
                ),
              );
            },
          );
        },
      ),

      // Tombol tambah catatan
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  // Form tambah (tidak berubah)
  void _showForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          top: 20,
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Judul'),
            ),

            TextField(
              controller: _contentController,
              decoration: const InputDecoration(labelText: 'Isi Catatan'),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              child: const Text("Simpan Catatan"),
              onPressed: () async {
                final String title = _titleController.text;
                final String content = _contentController.text;

                if (content.isNotEmpty) {
                  await _notes.add({
                    "title": title,
                    "content": content,
                    "timestamp": FieldValue.serverTimestamp(),
                  });

                  _titleController.clear();
                  _contentController.clear();
                  Navigator.of(context).pop();
                }
              },
            )
          ],
        ),
      ),
    );
  }

  // Form edit: muncul prefilled dan update dokumen dengan .update()
  void _showEditForm(DocumentSnapshot doc) {
    final TextEditingController editTitle = TextEditingController(text: doc['title'] ?? '');
    final TextEditingController editContent = TextEditingController(text: doc['content'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          top: 20,
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: editTitle,
              decoration: const InputDecoration(labelText: 'Judul'),
            ),

            TextField(
              controller: editContent,
              decoration: const InputDecoration(labelText: 'Isi Catatan'),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              child: const Text("Update Catatan"),
              onPressed: () async {
                final String title = editTitle.text;
                final String content = editContent.text;

                if (content.isNotEmpty) {
                  await _notes.doc(doc.id).update({
                    "title": title,
                    "content": content,
                    // jika ingin update timestamp:
                    "timestamp": FieldValue.serverTimestamp(),
                  });

                  Navigator.of(context).pop();
                }
              },
            )
          ],
        ),
      ),
    );
  }
}