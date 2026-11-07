import com.android.apksig.internal.apk.AndroidBinXmlParser;
import com.android.apksig.ApkVerifier;
import java.nio.ByteBuffer;
import java.util.zip.ZipFile;

class CiAndroidManifest {
    public static void main(String[] args) throws Exception {
        try (ZipFile apk = new ZipFile(args[0])) {
            var entry = apk.getEntry("AndroidManifest.xml");
            if (entry == null || entry.getSize() <= 0 || entry.getSize() > 4 * 1024 * 1024) {
                throw new IllegalArgumentException("Invalid manifest size");
            }
            byte[] bytes;
            try (var stream = apk.getInputStream(entry)) {
                bytes = stream.readNBytes(4 * 1024 * 1024 + 1);
            }
            if (bytes.length != entry.getSize()) throw new IllegalArgumentException("Invalid manifest bytes");
            var parser = new AndroidBinXmlParser(ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN));
            String packageName = null;
            String versionName = null;
            Integer versionCode = null;
            boolean versionCodeMajor = false;
            boolean manifest = false;
            while (parser.next() != AndroidBinXmlParser.EVENT_END_DOCUMENT) {
                if (parser.getEventType() != AndroidBinXmlParser.EVENT_START_ELEMENT ||
                    parser.getDepth() != 1 || !parser.getName().equals("manifest")) continue;
                if (manifest) throw new IllegalArgumentException("Duplicate manifest");
                manifest = true;
                for (int i = 0; i < parser.getAttributeCount(); i++) {
                    String name = parser.getAttributeName(i);
                    String namespace = parser.getAttributeNamespace(i);
                    if (name.equals("versionCodeMajor") || parser.getAttributeNameResourceId(i) == 0x01010576) {
                        if (versionCodeMajor) throw new IllegalArgumentException("Duplicate versionCodeMajor");
                        versionCodeMajor = true;
                        if (!name.equals("versionCodeMajor") ||
                            !"http://schemas.android.com/apk/res/android".equals(namespace) ||
                            parser.getAttributeNameResourceId(i) != 0x01010576 ||
                            parser.getAttributeValueType(i) != AndroidBinXmlParser.VALUE_TYPE_INT ||
                            parser.getAttributeIntValue(i) != 0) {
                            throw new IllegalArgumentException("Unsupported versionCodeMajor");
                        }
                    } else if (name.equals("package") && (namespace == null || namespace.isEmpty())) {
                        if (packageName != null) throw new IllegalArgumentException("Duplicate package");
                        packageName = parser.getAttributeStringValue(i);
                    } else if ("http://schemas.android.com/apk/res/android".equals(namespace)) {
                        if (name.equals("versionName")) {
                            if (versionName != null) throw new IllegalArgumentException("Duplicate versionName");
                            versionName = parser.getAttributeStringValue(i);
                        } else if (name.equals("versionCode")) {
                            if (versionCode != null) throw new IllegalArgumentException("Duplicate versionCode");
                            versionCode = parser.getAttributeIntValue(i);
                        }
                    }
                }
            }
            if (packageName == null || versionName == null || versionCode == null || versionCode <= 0 ||
                packageName.contains("\n") || packageName.contains("\r") ||
                versionName.contains("\n") || versionName.contains("\r")) {
                throw new IllegalArgumentException("Missing manifest identity");
            }
            System.out.println(packageName);
            System.out.println(versionName);
            System.out.println(versionCode);
            var result = new ApkVerifier.Builder(new java.io.File(args[0])).build().verify();
            if (!result.isVerified() || result.getSignerCertificates().size() != 1) {
                throw new IllegalArgumentException("Invalid APK signer");
            }
            var digest = java.security.MessageDigest.getInstance("SHA-256")
                .digest(result.getSignerCertificates().get(0).getEncoded());
            System.out.println(java.util.HexFormat.of().formatHex(digest));
        }
    }
}
