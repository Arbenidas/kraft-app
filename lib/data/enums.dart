/// Enumeraciones persistidas como texto: no renombres valores sin migración.
library;

enum ProjectKind {
  lienzo('LIENZO'),
  stylus('STYLUS'),
  nota('NOTA');

  const ProjectKind(this.label);
  final String label;
}

enum NoteCategory {
  idea('Ideas'),
  reunion('Reuniones'),
  boceto('Bocetos');

  const NoteCategory(this.label);
  final String label;
}

enum EventTag {
  lienzo('LIENZO'),
  urgente('URGENTE'),
  reunion('REUNIÓN'),
  nota('NOTA');

  const EventTag(this.label);
  final String label;
}
