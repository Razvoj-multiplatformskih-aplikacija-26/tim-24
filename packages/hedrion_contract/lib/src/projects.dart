import 'json.dart';

final class ProjectDto {
  const ProjectDto({
    required this.id,
    required this.name,
    required this.revision,
    this.ownerId,
  });

  final String id, name;
  final String? ownerId;
  final int revision;

  factory ProjectDto.fromJson(JsonObject json) => ProjectDto(
    id: string(json, 'id'),
    name: string(json, 'name'),
    ownerId: optionalString(json, 'ownerId'),
    revision: integer(json, 'revision', fallback: 1),
  );

  JsonObject toJson() => {
    'id': id,
    if (ownerId != null) 'ownerId': ownerId,
    'name': name,
    'revision': revision,
  };
}

final class ProjectWriteDto {
  const ProjectWriteDto({required this.name, this.baseRevision});

  final String name;
  final int? baseRevision;

  factory ProjectWriteDto.fromJson(JsonObject json) => ProjectWriteDto(
    name: string(json, 'name'),
    baseRevision: json['baseRevision'] is int
        ? json['baseRevision'] as int
        : null,
  );

  JsonObject toJson() => {
    'name': name,
    if (baseRevision != null) 'baseRevision': baseRevision,
  };
}

final class ProjectListDto {
  ProjectListDto(Iterable<ProjectDto> projects)
    : projects = List.unmodifiable(projects);

  final List<ProjectDto> projects;

  factory ProjectListDto.fromJson(JsonObject json) =>
      ProjectListDto(objects(json, 'projects').map(ProjectDto.fromJson));

  JsonObject toJson() => {
    'projects': projects.map((project) => project.toJson()).toList(),
  };
}
