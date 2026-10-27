# Arduino Uno の AES をアセンブリで読む

初学者向けの説明資料です。本編18枚、補足3枚の計21枚です。

- `AES_Assembly_Beginners.pptx`：編集可能な PowerPoint。全スライドに発表者ノートがあります。
- `AES_Assembly_Beginners.pdf`：閲覧・印刷用。同じ21枚を収録しています。
- `speaker_notes.md`：発表者ノートのテキスト版。
- `create_slides.py`：資料の再生成用スクリプト。Python 3、python-pptx、Pillow、Noto Sans CJK JP、DejaVu Sans Mono を使用します。

内容は、元の測定手順、アセンブリ化の意味、レジスタとメモリ、命令の読み方、
XOR の変更前後、ポインタ、ループ、AES の各演算、乱数生成、バッチ制御、
Arduino 標準機能との接続、検証結果の順に説明しています。

PowerPoint の「ノート」または「発表者ツール」で補足説明を確認できます。
PDF にはスライド本文を収録し、発表者ノートは収録していません。
日本語フォントは Noto Sans CJK JP です。未導入の Windows では、必要に応じて
PowerPoint のフォント置換で游ゴシックなどに変更してください。閲覧のみなら PDF が便利です。

説明対象は、この会話で作成した Arduino Uno / ATmega328P 用の `measurement.S` と、
添付原本 `Standard_AES_Measurement.ino` です。初期 AddRoundKey と第1ラウンドの測定用で、
AES-128 全10ラウンドの暗号化コードではありません。

シミュレータによる5500平文・55000パルスの比較結果を説明しています。
元プログラムとの実行時間や消費電力波形の一致、速度向上、実機での動作は主張していません。
資料の生成に伴い、元のソースコードと ZIP は変更していません。

この環境で Presentations プラグインは利用できなかったため、PowerPoint ファイルを直接生成しました。
PDF にレンダリングし、21ページすべてのテキストが保持されていることと、図・文字の配置を確認済みです。
