import 'package:apex_lsp/indexing/sobject_metadata.dart';
import 'package:xml/xml.dart';

/// Parses object-level metadata from the XML string of a *.object-meta.xml file.
///
/// The [apiName] is derived from the containing directory name rather than
/// the XML content, since object-meta.xml files do not include a fullName element.
SObjectMetadata parseObjectMetaXml(String apiName, String xmlContent) {
  final document = XmlDocument.parse(xmlContent);
  final root = document.rootElement;

  return SObjectMetadata(
    apiName: apiName,
    label: _childText(root, 'label'),
    pluralLabel: _childText(root, 'pluralLabel'),
    description: _childText(root, 'description'),
  );
}

/// Parses a single field from the XML string of a *.field-meta.xml file.
///
/// Returns null if the XML is malformed or if the required `fullName` element
/// is missing.
SObjectFieldMetadata? parseFieldMetaXml(String xmlContent) {
  if (xmlContent.isEmpty) return null;

  try {
    final document = XmlDocument.parse(xmlContent);
    final root = document.rootElement;

    final apiName = _childText(root, 'fullName');
    if (apiName == null) return null;

    return SObjectFieldMetadata(
      apiName: apiName,
      label: _childText(root, 'label'),
      type: _childText(root, 'type'),
      description: _childText(root, 'description'),
    );
  } on XmlException {
    return null;
  }
}

/// Returns the trimmed text content of the first child element with the given
/// local name, regardless of XML namespace. Returns null if no such element exists.
String? _childText(XmlElement parent, String localName) {
  final matches = parent.childElements.where(
    (element) => element.localName == localName,
  );
  if (matches.isEmpty) return null;
  final text = matches.first.innerText.trim();
  return text.isEmpty ? null : text;
}
