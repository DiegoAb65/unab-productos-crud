import os
import uuid
from flask import Flask, request, jsonify, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from werkzeug.utils import secure_filename

app = Flask(__name__)

# --- Configuración ---
basedir = os.path.abspath(os.path.dirname(__file__))
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///' + os.path.join(basedir, 'productos.db')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# Configuración de subida de imágenes
UPLOAD_FOLDER = os.path.join(basedir, 'uploads')
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}

# Crear carpeta de uploads si no existe
if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)

db = SQLAlchemy(app)

# Función auxiliar para verificar extensión
def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

# --- Modelo de Base de Datos ---
class Producto(db.Model):
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    nombre = db.Column(db.String(100), nullable=False)
    precio = db.Column(db.Float, nullable=False)
    cantidad = db.Column(db.Integer, nullable=False)
    # Nuevo campo: guardará el nombre del archivo (ej: "foto_123.jpg")
    imagen = db.Column(db.String(200), nullable=True) 

    def to_dict(self):
        # Generamos la URL completa para que el frontend pueda cargar la imagen
        # request.host_url devuelve "http://127.0.0.1:5000/" o la URL de ngrok
        imagen_url = None
        if self.imagen:
            imagen_url = f"{request.host_url}uploads/{self.imagen}"

        return {
            'id': self.id,
            'nombre': self.nombre,
            'precio': self.precio,
            'cantidad': self.cantidad,
            'imagen_url': imagen_url 
        }

# --- Rutas CRUD ---

# 1. Crear Producto (MULTIPART/FORM-DATA)
@app.route('/productos', methods=['POST'])
def create_producto():
    # Nota: Con multipart, usamos request.form para texto y request.files para archivos
    nombre = request.form.get('nombre')
    precio = request.form.get('precio')
    cantidad = request.form.get('cantidad')
    
    if not nombre or not precio or not cantidad:
        return jsonify({'error': 'Faltan datos obligatorios'}), 400

    # Procesar imagen
    nombre_archivo = None
    if 'imagen' in request.files:
        file = request.files['imagen']
        if file and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            # Para evitar duplicados, usamos un UUID corto en el nombre del archivo
            unique_filename = f"{uuid.uuid4().hex[:8]}_{filename}"
            file.save(os.path.join(app.config['UPLOAD_FOLDER'], unique_filename))
            nombre_archivo = unique_filename

    nuevo_producto = Producto(
        nombre=nombre,
        precio=float(precio),
        cantidad=int(cantidad),
        imagen=nombre_archivo
    )
    
    db.session.add(nuevo_producto)
    db.session.commit()
    
    return jsonify(nuevo_producto.to_dict()), 201

# 2. Leer todos
@app.route('/productos', methods=['GET'])
def get_productos():
    productos = Producto.query.all()
    return jsonify([p.to_dict() for p in productos]), 200

# 3. Leer uno
@app.route('/productos/<string:id>', methods=['GET'])
def get_producto(id):
    producto = Producto.query.get_or_404(id)
    return jsonify(producto.to_dict()), 200

# 4. Actualizar (MULTIPART/FORM-DATA)
@app.route('/productos/<string:id>', methods=['PUT'])
def update_producto(id):
    producto = Producto.query.get_or_404(id)
    
    # Textos
    producto.nombre = request.form.get('nombre', producto.nombre)
    if request.form.get('precio'):
        producto.precio = float(request.form.get('precio'))
    if request.form.get('cantidad'):
        producto.cantidad = int(request.form.get('cantidad'))

    # Imagen (Si envían una nueva, reemplazamos la anterior)
    if 'imagen' in request.files:
        file = request.files['imagen']
        if file and allowed_file(file.filename):
            # 1. Borrar imagen vieja si existe
            if producto.imagen:
                old_path = os.path.join(app.config['UPLOAD_FOLDER'], producto.imagen)
                if os.path.exists(old_path):
                    os.remove(old_path)
            
            # 2. Guardar nueva
            filename = secure_filename(file.filename)
            unique_filename = f"{uuid.uuid4().hex[:8]}_{filename}"
            file.save(os.path.join(app.config['UPLOAD_FOLDER'], unique_filename))
            producto.imagen = unique_filename

    db.session.commit()
    return jsonify(producto.to_dict()), 200

# 5. Eliminar (Borra registro y archivo físico)
@app.route('/productos/<string:id>', methods=['DELETE'])
def delete_producto(id):
    producto = Producto.query.get_or_404(id)
    
    # Intentar borrar el archivo físico
    if producto.imagen:
        file_path = os.path.join(app.config['UPLOAD_FOLDER'], producto.imagen)
        if os.path.exists(file_path):
            try:
                os.remove(file_path)
            except Exception as e:
                print(f"Error borrando archivo: {e}")

    db.session.delete(producto)
    db.session.commit()
    return jsonify({'mensaje': 'Producto eliminado correctamente'}), 200

# 6. RUTA PARA SERVIR IMÁGENES (Para que Flutter pueda verlas)
@app.route('/uploads/<filename>')
def uploaded_file(filename):
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
    app.run(debug=True, port=5000)