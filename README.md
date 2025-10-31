# Vib SNS

Vib SNSは、ニンテンドー3DSの「すれちがい通信」にインスパイアされたFlutterプロトタイプアプリです。近くのプレイヤーとの出会いの瞬間—プロフィールを確認し、いいねを送り、フォローする—に焦点を当てています。

## 機能

- **すれちがい通信風の出会い**: ローカルユーザーの存在（位置情報、プロフィールメタデータ、BLEビーコンID）をFirestoreに公開し、アプリ実行中は常に最新の状態に保ちます
- **ハイブリッド近接検知**: GPS距離測定（Geolocator）と高精度BLE近接検知（flutter_blue_plus + flutter_ble_peripheral）を組み合わせて、すれちがい通信風の接触検知を実現
- **プロフィール管理**: 表示名、自己紹介、出身地、好きなゲーム、アバターでプロフィールを作成・編集
- **プロフィール画像**: image_pickerを使用してカスタムプロフィール画像をアップロード
- **ソーシャルインタラクション**: Firestoreによるリアルタイム同期でユーザーをフォローしたり、いいねを送信
- **タイムライン**: 最近の出会いやインタラクションを時系列で表示
- **マップビュー**: flutter_mapを使用したインタラクティブマップで出会ったユーザーを表示
- **QRコード**: QRコードでプロフィールを共有
- **認証**: セキュアなユーザー管理のためのFirebase匿名認証
- **ログアウト**: サインアウトしてローカルデータをクリア
- **モックモード**: Firebase/Bluetoothが利用できない場合でも、モックのすれちがい通信とBLEストリームにフォールバックするため、UIのテストが可能
- **状態管理**: 共有アプリケーション状態にProviderを使用し、UIレイヤーにMaterial 3を採用

## はじめに

```bash
flutter pub get
```

### 実際のすれちがい通信動作を有効にする

1. Firebaseプロジェクトを作成し、アプリを登録します（Android/iOS/Webなど必要に応じて）。
2. ネイティブ設定ファイルを配置: `android/app/google-services.json` および/または `ios/Runner/GoogleService-Info.plist`。
3. FlutterFireで`lib/firebase_options.dart`を生成:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
4. Cloud FirestoreとFirebase Authentication（匿名サインイン）を有効にします。アプリは2つの主要なコレクションを使用します：

   **プロフィールコレクション** (`profiles/{deviceId}`):
   ```json
   {
     "id": "device-id",
     "displayName": "あなた",
     "bio": "...",
     "homeTown": "...",
     "favoriteGames": ["スプラトゥーン3", "マリオカート8 デラックス"],
     "avatarColor": 305419896,
     "photoUrl": "https://...",
     "beaconId": "uuid-...",
     "authUid": "firebase-auth-uid",
     "followedBy": ["device-id-1", "device-id-2"],
     "receivedLikes": 3
   }
   ```

   **すれちがい通信プレゼンスコレクション** (`streetpass_presences/{deviceId}`):
   ```json
   {
     "profile": {
       "id": "device-id",
       "displayName": "あなた",
       "bio": "...",
       "homeTown": "...",
       "favoriteGames": ["スプラトゥーン3", "マリオカート8 デラックス"],
       "avatarColor": 305419896,
       "photoUrl": "https://...",
       "following": false,
       "receivedLikes": 0
     },
     "lat": 35.0,
     "lng": 135.0,
     "lastUpdatedMs": 1690000000000,
     "active": true
   }
   ```

   開発専用ルール（本番環境では使用しないでください）：

   ```text
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /streetpass_presences/{deviceId} {
         allow read, write;
       }
       match /profiles/{deviceId} {
         allow read, write;
       }
     }
   }
   ```

5. （オプション）プロフィール削除などのサーバーサイド操作のためにCloud Functionsをデプロイ：
   ```bash
   cd functions
   npm install
   firebase deploy --only functions
   ```

6. 位置情報とBluetooth権限をリクエスト：
   - **Android**: 以下を`AndroidManifest.xml`に追加（minSdk/targetSdkに応じて調整）：
     ```xml
     <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
     <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
     <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
     <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
     <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
     ```
     Android 12以上をターゲットにする場合、必要に応じて`BLUETOOTH_SCAN`に`android:usesPermissionFlags="neverForLocation"`を追加してください。
   - **iOS**: `Info.plist`に`NSLocationWhenInUseUsageDescription`、`NSBluetoothAlwaysUsageDescription`、`NSBluetoothPeripheralUsageDescription`、`NSPhotoLibraryUsageDescription`を追加。

アプリの起動：

```bash
flutter run
```

初回起動時に位置情報の権限プロンプトが表示されます。拒否すると、権限が付与されるまでアプリはエラー状態になります。

## 仕組み

- **認証**: `FirebaseAuth`は匿名サインインを提供し、サーバーサイドの検証のためにプロフィールを認証UIDに関連付けます
- **プロフィール永続化**: `LocalProfileLoader`は、SharedPreferencesを使用してローカルプロフィール（表示名、出身地、好きなゲーム、アバター色、ビーコンID）を永続化し、各デバイスが一貫したアイデンティティを保持します
- **プロフィールインタラクション**: `FirestoreProfileInteractionService`は、いいね、フォロー、プロフィール更新をFirestoreにリアルタイムで同期します
- **すれちがい通信検知**: `FirestoreStreetPassService`は、デバイスのプレゼンス（BLEビーコンIDを含む）を更新し、近くのユーザーをポーリングします。GPS距離はGeolocatorプラグインを介してローカルで計算されます
- **BLE近接**: `BleProximityScannerImpl`は、コンパクトなビーコンUUIDをアドバタイズし、flutter_blue_plusを介して一致するUUIDを継続的にスキャンし、RSSIをサブメートルの距離推定値に変換します
- **出会いの融合**: `EncounterManager`は、GPSとBLE信号を融合し、BLEヒットが観測されると出会いを「近く」にアップグレードし、UIにフォロー/いいねトグルを公開します
- **タイムライン**: `TimelineManager`は、最近の出会いとインタラクションを追跡し、時系列で表示します
- **通知**: `NotificationManager`は、バッジ表示のために未読のいいねとフォローを追跡します
- **モックフォールバック**: `MockStreetPassService` / `MockBleProximityScanner`は、FirebaseまたはBluetoothが利用できない場合にUIをインタラクティブに保ちます

## アーキテクチャ

```
lib/
├── main.dart                    # アプリのエントリーポイント、Firebase初期化
├── models/
│   ├── profile.dart            # プロフィールデータモデル
│   ├── encounter.dart          # 出会いデータモデル
│   └── timeline_event.dart     # タイムラインイベントデータモデル
├── screens/
│   ├── home_shell.dart         # メインナビゲーションシェル
│   ├── name_setup_screen.dart  # 初期プロフィール設定
│   ├── profile_edit_screen.dart # プロフィール編集
│   ├── encounters_screen.dart  # 近くのユーザーリスト
│   ├── timeline_screen.dart    # タイムラインフィード
│   └── map_screen.dart         # マップビュー
├── services/
│   ├── streetpass_service.dart              # すれちがい通信インターフェース
│   ├── firestore_streetpass_service.dart    # 実際のFirestore実装
│   ├── mock_streetpass_service.dart         # モック実装
│   ├── profile_interaction_service.dart     # プロフィールインタラクションインターフェース
│   ├── firestore_profile_interaction_service.dart # 実際のFirestore実装
│   ├── mock_profile_interaction_service.dart # モック実装
│   ├── ble_proximity_scanner.dart           # BLEスキャナーインターフェース
│   ├── ble_proximity_scanner_impl.dart      # 実際のBLE実装
│   └── mock_ble_proximity_scanner.dart      # モックBLE実装
├── state/
│   ├── encounter_manager.dart   # 出会い状態の管理
│   ├── local_profile_loader.dart # ローカルプロフィールの読み込み/保存
│   ├── profile_controller.dart  # プロフィール状態管理
│   ├── timeline_manager.dart    # タイムライン状態管理
│   ├── notification_manager.dart # 通知バッジ管理
│   └── runtime_config.dart      # ランタイム設定
└── widgets/
    └── profile_avatar.dart      # アバター表示ウィジェット
```

## 今後の課題

1. メッセージングやグループ出会いなど、より多くのソーシャル機能を追加
2. 新しい出会いのためのプッシュ通知を実装
3. ディスカバリーとバッテリー寿命のバランスを取るためにポーリング頻度とバックグラウンド動作を最適化
4. プライバシーコントロール（透明モード、ブロックリスト）を追加
5. 本番環境用の適切なFirestoreセキュリティルールを実装
6. 分析とエラー報告を追加

## ライセンス

これは教育目的のプロトタイププロジェクトです。
