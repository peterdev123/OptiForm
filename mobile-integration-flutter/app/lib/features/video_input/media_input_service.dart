import 'package:image_picker/image_picker.dart';

class MediaInputService {
  MediaInputService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<XFile?> pickPoseImage() {
    return _picker.pickImage(source: ImageSource.gallery);
  }

  Future<XFile?> pickSquatVideo() {
    return _picker.pickVideo(source: ImageSource.gallery);
  }
}
