/// Comparación de textos "a lo humano": sirve para reconocer de qué habla el usuario
/// ("el diagrama de la calculadora") y para no duplicar cosas que ya existen con otro nombre.
library;

const _stopWords = {
  'de',
  'del',
  'la',
  'el',
  'los',
  'las',
  'un',
  'una',
  'unos',
  'unas',
  'y',
  'o',
  'en',
  'con',
  'para',
  'por',
  'que',
  'mi',
  'mis',
  'tu',
  'sus',
  'su',
  'al',
  'lo',
  'sobre',
  'como',
  'este',
  'esta',
  'ese',
  'esa',
  'esto',
  'nota',
  'notas',
  'lienzo',
  'lienzos',
  'diagrama',
  'diagramas',
  'proyecto',
  'proyectos',
  'tarea',
  'tareas',
};

const _accents = {
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
};

/// Minúsculas, sin acentos: "Arquitectura Tecnológica" → "arquitectura tecnologica".
String normalize(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_accents[ch] ?? ch);
  }
  return buffer.toString();
}

/// Palabras con contenido: sin acentos, sin artículos ni muletillas, de tres letras o más.
Set<String> keywords(String text) => {
  for (final word in normalize(text).split(RegExp(r'[^a-z0-9]+')))
    if (word.length >= 3 && !_stopWords.contains(word)) word,
};

/// Cuánto se parecen dos conjuntos de palabras: 1 = uno contiene al otro, 0 = nada en común.
/// Se divide por el más corto para que "Calculadora" siga reconociendo "Arquitectura de la calculadora".
double overlap(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final shared = a.where(b.contains).length;
  return shared / (a.length < b.length ? a.length : b.length);
}

/// Puntúa [text] frente a lo que busca el usuario: cuenta las palabras encontradas y
/// premia que aparezca la frase entera.
double score(Set<String> wanted, String text) {
  if (wanted.isEmpty) return 0;
  final haystack = normalize(text);
  var hits = 0;
  for (final word in wanted) {
    if (haystack.contains(word)) hits++;
  }
  return hits / wanted.length;
}
