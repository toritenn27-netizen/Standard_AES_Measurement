# AES 第1ラウンド・段階別出力テスト（AVR アセンブリ）

Arduino Uno（ATmega328P、16 MHz）で、1平文について初期 AddRoundKey と
第1ラウンドのみを実行し、各段階の16バイトをシリアル出力する動作確認用スケッチです。
既存の測定用コードは変更していません。

## Arduino IDE で使う

1. ZIP を展開します。
2. `AES_Round1_Stage_Test_ASM` フォルダー内の
   `AES_Round1_Stage_Test_ASM.ino` を Arduino IDE で開きます。
3. 同じフォルダーに `stage_test.S` があることを確認します。拡張子の S は大文字です。
4. ボードを **Arduino Uno**、ポートを接続中の Uno に設定し、検証・書き込みします。
5. シリアルモニタを **115200 baud** に設定して開きます。
6. 大文字 **`S`** を1回送ると、新しい平文1つについて1回だけテストします。
7. モニタを開いたまま再度 **`S`** を送ると、次の平文で再テストします。

改行あり・なしのどちらでも使用できます。小文字 `s` や改行など、`S` 以外の文字は無視します。
`SS` と送ると2回分のテストになります。自動連続実行は行いません。

対象は従来型 Uno です。Uno R4 は対象外です。
Arduino IDE 自体での書き込み操作は、このクラウドでは実施していません。

## 出力される内容と順序

| 表示名 | 内容 |
|---|---|
| `Plaintext` | 今回生成した元の平文16バイト |
| `Key (Round 0)` | 指定されたマスター鍵16バイト |
| `Key (Round 1)` | マスター鍵から生成した第1ラウンド鍵 |
| `Initial AddRoundKey (R0)` | 平文とマスター鍵を XOR した状態 |
| `SubBytes (R1)` | 標準 S-Box で置換した状態 |
| `ShiftRows (R1)` | 各行を並べ替えた状態 |
| `MixColumns (R1)` | 各列を混合した状態 |
| `AddRoundKey (R1)` | 第1ラウンド鍵を XOR した状態（今回の最終出力） |

表示はゼロ埋め大文字16進数、バイト間に空白を入れた形式です。
各行の16バイトは `state[0]`〜`state[15]` の順です。
AES の4×4状態行列を考えるときは、列方向に並べた順序です。

```text
state[0] state[4] state[8]  state[12]
state[1] state[5] state[9]  state[13]
state[2] state[6] state[10] state[14]
state[3] state[7] state[11] state[15]
```

初回の出力全体は `example_output.txt` を参照してください。
初回平文は `7A AF A0 EA D3 62 98 38 78 4C BE DF 42 67 0B FC`、
第1ラウンド終了時の状態は `1C A1 75 39 18 09 34 2A 6C 35 31 92 98 99 A1 95` です。

## 鍵

指定された固定の AES-128 鍵を使います。

```text
2B 7E 15 16 28 AE D2 A6 AB F7 15 88 09 CF 4F 3C
```

第1ラウンド鍵を表として固定しているのではなく、アセンブリで
RotWord、SubWord、Rcon=01 を使って生成します。生成結果は次のとおりです。

```text
A0 FA FE 17 88 54 2C B1 23 A3 39 39 2A 6C 76 05
```

## 平文が変わる仕組み

初期シード12345の xorshift32 を使用し、16回呼び出した各結果の下位1バイトを
集めて平文を作ります。`S` を送ってもシードを戻さず、次の16バイトへ進みます。
テストを再現しやすい疑似乱数列で、暗号用途の安全な乱数生成器ではありません。

**リセット・再起動・再書き込みでは、最初の平文に戻ります。**
Uno はシリアルモニタの開き直しで自動リセットされることがあるため、
平文を変えて再テストしたい場合は、モニタを開いたまま `S` を再送してください。

## 測定用スケッチとの違い

- 1コマンドにつき1平文・1回だけ実行します。
- 初期 XOR と第1ラウンドだけです。AES-128 全10ラウンドの暗号文ではありません。
- 各段階を別々のメモリに保存した後、まとめて表示します。
- **D5 のトリガーや測定用の10 ms待機はありません。** 段階別の結果確認専用です。
- `.S` が AES、鍵展開、平文生成、状態保存、出力順序を実装します。
  `.ino` は Arduino 標準の Serial と起動処理を呼ぶ接続部分です。
- 使用する2ファイルはこのフォルダー内で完結し、元の測定用フォルダーを必要としません。

## ビルドと検証

Linux で AVR GCC、binutils-avr、avr-libc、Arduino AVR Core、Python 3 を導入後、
この README のあるディレクトリで実行できます。

```sh
python3 tools/build.py --sketch AES_Round1_Stage_Test_ASM --output build/stage-test
```

独自のツール配置では `AVR_PREFIX` と `ARDUINO_AVR_ROOT` で指定できます。

```sh
export AVR_PREFIX=/path/to/toolchain/bin/avr-
export ARDUINO_AVR_ROOT=/path/to/arduino/hardware/arduino/avr
```

ホストの GCC と libsimavr-dev も導入すると、シミュレータによる検証を再実行できます。

```sh
python3 tests/run_stages.py
# simavr が独自の場所にある場合：
python3 tests/run_stages.py --simavr-prefix /path/to/prefix/usr
```

実行済みの検証は以下です。

1. ATmega328P 向けにビルド成功（AVR GCC 14.2.0 / Arduino AVR Core 1.8.7）。
2. simavr 1.6 で `S` を100回送信し、100平文がそれぞれ1回だけ処理されることを確認。
3. 全100平文の元データ、両方の鍵、5つの中間状態を独立した Python の AES 計算と照合。
4. FIPS 197（2001年版）Appendix B の平文 `3243F6A8885A308D313198A2E0370734`
   をシミュレータの SRAM に注入し、公表済みの全中間値との一致を確認。
   この既知値注入はホスト側のテストだけで行い、スケッチのコードは変更していません。
5. `S` 以外の文字で実行されず、待機中に自動再実行しないことを確認。

ビルド結果は Flash 3806バイト、静的 SRAM 336バイトでした。
実機への書き込み・物理的な Uno 上での動作確認は未実施です。
