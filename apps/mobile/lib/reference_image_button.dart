import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'app_connection.dart';

class ReferenceImageButton extends StatefulWidget {
  const ReferenceImageButton({super.key, required this.asset});
  final Asset asset;
  @override
  State<ReferenceImageButton> createState() => _ReferenceImageButtonState();
}

class _ReferenceImageButtonState extends State<ReferenceImageButton> {
  bool busy = false;
  Future<void> upload() async {
    final api = StudioConnection.maybeOf(context)!.client!;
    setState(() => busy = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        requestFullMetadata: false,
      );
      if (image == null) {
        return;
      }
      final bytes = await image.readAsBytes();
      if (bytes.length > 10000000) {
        throw const DomainException(DomainError(ErrorCode.invalidInput));
      }
      await api.uploadImage(
        widget.asset.id,
        bytes,
        mime: bytes.length > 2 && bytes[0] == 137 ? 'image/png' : 'image/jpeg',
      );
      if (mounted) {
        context.read<AssetBloc>().add(const LoadAssets());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Referentna slika je sačuvana. Možeš zatražiti generisanje.',
            ),
          ),
        );
      }
    } on DomainException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e.error))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Slika nije dostupna. Proverite dozvolu ili izaberite PNG/JPEG do 10 MB.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: busy ? null : upload,
    icon: const Icon(Icons.add_photo_alternate_outlined),
    label: Text(busy ? 'Slanje slike…' : 'Postavi referentnu sliku'),
  );
}
