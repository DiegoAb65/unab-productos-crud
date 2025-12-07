import 'dart:convert';
import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart'; // <--- Importamos image_picker

// --- CONFIGURACIÓN DE COLORES UNAB ---
const Color unabBlue = Color(0xFF002D72);
const Color unabRed = Color(0xFFE30613);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Productos UNAB',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: unabBlue, primary: unabBlue),
        appBarTheme: const AppBarTheme(
          backgroundColor: unabBlue,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 4,
        ),
      ),
      home: const ProductListScreen(),
    );
  }
}

// --- 1. MODELO ACTUALIZADO ---
class Producto {
  final String? id;
  final String nombre;
  final double precio;
  final int cantidad;
  final String? imagenUrl; // Nuevo campo para la URL de la imagen

  Producto({
    this.id, 
    required this.nombre, 
    required this.precio, 
    required this.cantidad,
    this.imagenUrl
  });

  factory Producto.fromJson(Map<String, dynamic> json) {
    return Producto(
      id: json['id'],
      nombre: json['nombre'],
      precio: (json['precio'] as num).toDouble(),
      cantidad: json['cantidad'],
      imagenUrl: json['imagen_url'], // Mapeamos lo que viene de Flask
    );
  }
}

// --- 2. SERVICIO API (MULTIPART) ---
class ApiService {
  // PON TU URL DE NGROK ACTUALIZADA
  static const String baseUrl = "https://6d475526172a.ngrok-free.app"; 

  // Headers simples para GET
  static const Map<String, String> headers = {
    "ngrok-skip-browser-warning": "true",
  };

  static Future<List<Producto>> getProductos() async {
    final response = await http.get(Uri.parse('$baseUrl/productos'), headers: headers);
    if (response.statusCode == 200) {
      final List<dynamic> body = jsonDecode(response.body);
      return body.map((e) => Producto.fromJson(e)).toList();
    } else {
      throw Exception('Error al cargar productos');
    }
  }

  // Método genérico para enviar Multipart (Crear o Actualizar)
  static Future<void> submitProduct(String method, Producto prod, File? imageFile) async {
    
    // Definir URL dependiendo si es crear o actualizar
    final url = (method == 'POST') 
        ? Uri.parse('$baseUrl/productos')
        : Uri.parse('$baseUrl/productos/${prod.id}');

    // Creamos la petición Multipart
    var request = http.MultipartRequest(method, url);
    
    // Agregamos campos de texto
    request.fields['nombre'] = prod.nombre;
    request.fields['precio'] = prod.precio.toString();
    request.fields['cantidad'] = prod.cantidad.toString();

    // Headers de ngrok (importante ponerlo en el request.headers)
    request.headers.addAll(headers);

    // Agregamos la imagen si el usuario seleccionó una nueva
    if (imageFile != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'imagen', // El nombre del campo que espera Flask
          imageFile.path
        )
      );
    }

    // Enviamos
    final streamResponse = await request.send();
    
    if (streamResponse.statusCode != 200 && streamResponse.statusCode != 201) {
      // Leemos el error del servidor si falla
      final respStr = await streamResponse.stream.bytesToString();
      throw Exception('Error $method: $respStr');
    }
  }

  static Future<void> deleteProducto(String id) async {
    final response = await http.delete(Uri.parse('$baseUrl/productos/$id'), headers: headers);
    if (response.statusCode != 200) throw Exception('Error al eliminar');
  }
}

// --- UTILIDADES ---
Future<bool> showConfirmationDialog(BuildContext context, String title, String content) async {
  return await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: unabBlue, foregroundColor: Colors.white),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text("Confirmar"),
        ),
      ],
    ),
  ) ?? false;
}

// --- 3. UI: LISTA ---
class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  late Future<List<Producto>> _futureProductos;

  @override
  void initState() {
    super.initState();
    _refreshList();
  }

  void _refreshList() {
    setState(() {
      _futureProductos = ApiService.getProductos();
    });
  }

  void _confirmAndDelete(String id) async {
    bool confirm = await showConfirmationDialog(
      context, "Eliminar", "¿Eliminar producto y su imagen permanentemente?");
    if (confirm) {
      try {
        await ApiService.deleteProducto(id);
        _refreshList();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eliminado')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Productos UNAB')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: unabBlue,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductFormScreen()));
          _refreshList();
        },
      ),
      body: FutureBuilder<List<Producto>>(
        future: _futureProductos,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('Sin productos'));

          final list = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.all(10),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final prod = list[index];
              return Card(
                child: ListTile(
                  // Mostramos imagen si existe, sino un icono
                  leading: SizedBox(
                    width: 50, height: 50,
                    child: prod.imagenUrl != null
                        ? Image.network(prod.imagenUrl!, fit: BoxFit.cover, 
                            errorBuilder: (c,o,s) => const Icon(Icons.broken_image))
                        : const Icon(Icons.image_not_supported, color: Colors.grey),
                  ),
                  title: Text(prod.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('\$${prod.precio} | Stock: ${prod.cantidad}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit, color: Colors.amber), onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(producto: prod)));
                        _refreshList();
                      }),
                      IconButton(icon: const Icon(Icons.delete, color: unabRed), onPressed: () => _confirmAndDelete(prod.id!)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// --- 4. UI: FORMULARIO CON IMAGEN ---
class ProductFormScreen extends StatefulWidget {
  final Producto? producto;
  const ProductFormScreen({super.key, this.producto});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _cantCtrl = TextEditingController();
  
  // Variables para manejo de imagen
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.producto != null) {
      _nombreCtrl.text = widget.producto!.nombre;
      _precioCtrl.text = widget.producto!.precio.toString();
      _cantCtrl.text = widget.producto!.cantidad.toString();
    }
  }

  // Función para seleccionar imagen
  Future<void> _pickImage(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(source: source, imageQuality: 50); // Bajamos calidad para rapidez
    if (picked != null) {
      setState(() {
        _selectedImage = File(picked.path);
      });
    }
  }

  // Diálogo para elegir origen
  void _showImageSourceOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galería'),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Cámara'),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); },
            ),
          ],
        ),
      ),
    );
  }

  void _save() async {
    if (_formKey.currentState!.validate()) {
      final isEditing = widget.producto != null;

      if (isEditing) {
        bool confirm = await showConfirmationDialog(context, "Confirmar", "¿Actualizar datos del producto?");
        if (!confirm) return;
      }

      final nuevoProducto = Producto(
        id: widget.producto?.id,
        nombre: _nombreCtrl.text,
        precio: double.parse(_precioCtrl.text),
        cantidad: int.parse(_cantCtrl.text),
      );

      try {
        await ApiService.submitProduct(
          isEditing ? 'PUT' : 'POST', 
          nuevoProducto, 
          _selectedImage // Pasamos la imagen seleccionada (puede ser null)
        );
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.producto != null;
    
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Editar Producto UNAB' : 'Nuevo Producto UNAB')),
      body: SingleChildScrollView( // Importante para que el teclado no tape
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // --- SELECCIONAR IMAGEN ---
              GestureDetector(
                onTap: _showImageSourceOptions,
                child: Container(
                  width: 150, height: 150,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: unabBlue, width: 2)
                  ),
                  child: _selectedImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_selectedImage!, fit: BoxFit.cover)) // 1. Imagen Local (Nueva)
                      : (widget.producto?.imagenUrl != null)
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(widget.producto!.imagenUrl!, fit: BoxFit.cover)) // 2. Imagen Remota (Existente)
                          : const Column( // 3. Placeholder
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo, size: 40, color: Colors.grey),
                                Text("Agregar Foto", style: TextStyle(color: Colors.grey))
                              ],
                            ),
                ),
              ),
              const SizedBox(height: 20),
              
              // --- CAMPOS DE TEXTO ---
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder(), prefixIcon: Icon(Icons.label)),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _precioCtrl,
                decoration: const InputDecoration(labelText: 'Precio', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
                keyboardType: TextInputType.number,
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _cantCtrl,
                decoration: const InputDecoration(labelText: 'Cantidad', border: OutlineInputBorder(), prefixIcon: Icon(Icons.numbers)),
                keyboardType: TextInputType.number,
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 30),
              
              // --- BOTON ---
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: unabBlue, foregroundColor: Colors.white),
                  onPressed: _save,
                  child: Text(isEditing ? 'ACTUALIZAR' : 'GUARDAR', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}