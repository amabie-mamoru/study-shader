/// <summary>
/// Toon Shader see: ※1
/// Roystan さんのトゥーンシェーダーチュートリアルを手元の Unity でごにょごにょいじりながら日本語解説を入れた奴
/// 正直まだよくわかっていない部分も多分にあるが、ひとまず流れと雰囲気は掴めたのでアップして見返せるようにしておく
/// </summary>
Shader "Roystan/Toon Complete"
{
	Properties
	{
		_Color("Color", Color) = (1,1,1,1)
		_MainTex("Main Texture", 2D) = "white" {}

		// 周囲光と呼ばれる領域内のオブジェクトの表面で跳ね返り、大気中で散乱する光を設定可能にする
		// これにより影が真っ黒になるのを防ぐ ※1
		// この値の設定次第で影の色味が変わる

		[HDR]
		_AmbientColor("Ambient Color", Color) = (0.4,0.4,0.4,1)

		// ハイライトの色味

		[HDR]
		_SpecularColor("Specular Color", Color) = (0.9,0.9,0.9,1)

		// ハイライトの光沢の大きさ

		_Glossiness("Glossiness", Float) = 32

		// リム（縁取り）の色

		[HDR]
		_RimColor("Rim Color", Color) = (1,1,1,1)

		// リムの幅

		_RimAmount("Rim Amount", Range(0, 1)) = 0.716

		// 縁取りの量 0: 影ギリギリまで幅がっつりリム、1: 光があたる方向に最小限のリム

		_RimThreshold("Rim Threshold", Range(0, 1)) = 0.1		
	}
	SubShader
	{
		Pass
		{
			/// <summary>
			/// ライト1つ、DirectionalLight を想定してるよーって記述。see: ※2
			/// ライト2つ以上参照したい場合は ForwardAdd を検討。ただし処理は重くなる
			/// </summary>

			Tags
			{
				"LightMode" = "ForwardBase"
				"PassFlags" = "OnlyDirectional"
			}

			CGPROGRAM

			/// <summary>
			/// 頂点シェーダーとフラグメントシェーダーの定義（必須のやつ）see: ※2
			/// 復習として vert は頂点ごとに呼ばれるが frag はピクセルごとに呼ばれるので呼び出し回数に注意!!
			/// </summary>

			#pragma vertex vert
			#pragma fragment frag

			// PassType.ForwardBase のときに様々なキーワード群を追加するための宣言 see: ※3
			// これにより ForwardBase に必要なすべてのバリアントをコンパイルするよう Unity に指示することで
			// シャドウマップの値をサンプリングして、ライティングの計算に適応できる

			#pragma multi_compile_fwdbase

			// ヘルパー関数群 see: ※2

			#include "UnityCG.cginc"

			// ワールド座標の色味を反映する _LightColor0 を参照するために必要なヘルパー see: ※1

			#include "Lighting.cginc"

			// ライティングとシャドウまわりの関数群 see: ※2
			// ここでは SHADOW_COORDS, TRANSFER_SHADOW, SHADOW_ATTENUATION を使うために include

			#include "AutoLight.cginc"

			struct appdata
			{
				float4 vertex : POSITION;				
				float4 uv : TEXCOORD0;
				float3 normal : NORMAL;
			};

			struct v2f
			{
				float4 pos : SV_POSITION;
				float3 worldNormal : NORMAL;
				float2 uv : TEXCOORD0;
				float3 viewDir : TEXCOORD1;	
				// プラットフォームに応じて様々な精度で4次元の値を生成し
				// 提供されたインデックス(今回は 2)でTEXCOORD瀬マンティクスに割り当てる
				SHADOW_COORDS(2)
			};

			sampler2D _MainTex;
			float4 _MainTex_ST;
			
			v2f vert (appdata v)
			{
				v2f o;
				o.pos = UnityObjectToClipPos(v.vertex);

				// v はオブジェクト空間(モデル空間)の座標系であり、その法線は v.normal である
				// 面の方向を知りたいのでオブジェクト空間の法線をワールド空間の座標へと変換する
				// こうすることで、ワールド空間の座標比較ができるのでフラグメントシェーダーでライトの方向と比較するために使う
				// see: ※1

				o.worldNormal = UnityObjectToWorldNormal(v.normal);

				// 鏡面反射(いわゆるハイライト)を実現するために現在の座標からカメラに向かう方向ベクトルをフラグメントシェーダーに渡す

				o.viewDir = WorldSpaceViewDir(v.vertex);

				o.uv = TRANSFORM_TEX(v.uv, _MainTex);

				// TRANSFER_SHADOW は入力頂点の空間をシャドウマップの空間に変換し、宣言した SHADOW_COORD に格納する

				TRANSFER_SHADOW(o)
				return o;
			}
			
			float4 _Color;

			float4 _AmbientColor;

			float4 _SpecularColor;
			float _Glossiness;		

			float4 _RimColor;
			float _RimAmount;
			float _RimThreshold;	

			float4 frag (v2f i) : SV_Target
			{
				// オブジェクトの法線ベクトル
				// normalize(v) はベクトル v と同じ方向を指す長さ1のベクトルを返す ※2
				// よって正規化された方向だけを識別するための法線ベクトルを得る (-1 <= normal <= 1)

				float3 normal = normalize(i.worldNormal);
				float3 viewDir = normalize(i.viewDir);

				// dot(a, b) は内積の演算を行う関数 ※2
				// ワールド座標系の光源座標 x と 法線ベクトルの内積
				// これによりリアルなイルミネーションを実現する（物質の色だけでなく、影と光のグラデーションを表現する）

				float NdotL = dot(_WorldSpaceLightPos0, normal);

				// SHADOW_ATTENUATION は影がないと 0、完全に影があると 1 を返すマクロ
				// NdotL はメインのディレクショナルライトから受け取った光の量を格納しているため
				// lightIntensity を求めるときに NdotL に掛け合わせることで他の物質から影のときに影を落とす表現ができるようになる

				float shadow = SHADOW_ATTENUATION(i);

				// トゥーン風に仕上げる ※1
				// float lightIntensity = NdotL > 0 ? 1 : 0; みたいにすると 2階調のトゥーンレンダリングも可能
				// ただ、上記の表現にした場合、影が真っ黒になってしまったり、光が当たる面と影の境界がはっきりしすぎてしまう
				// smoothstep 関数は明るい部分と暗い部分の境界を柔らかくする
				// NdotL > 0 ? 1 : 0; みたいにすると 2階調なので、境界がピクセルごとに 0 か 1 にしかならないのでギザギザになる
				// smoothstep を使えば、境界だけ 0.7 や 0.5 みたいなブレンドを実現できるので線が人間の目で見ると滑らかに見えるようになる
				// 特に今回は 0〜0.01 までの間だけ適応するという記述なので、基本は NdotL > 0 ? 1 : 0; の 2階調にわけるように表現し
				// 0〜0.01までの間 (内積が 0.0003 とかの値)のときのみスムーズになるように馴染ませる
				// トゥーンな感じを残すために 0〜0.01 だけ適応しているが、普段は (0, 1, value) みたいな感じで全体的に適応することが多い

				float lightIntensity = smoothstep(0, 0.01, NdotL * shadow);

				// _LightColor0 は DirectionLight の色味
				// これによって DirectionLight の色味を物体に反映できる

				float4 light = lightIntensity * _LightColor0;

				// 鏡面反射(ハイライト)の強さに関しては、表面の法線とハーフベクトルの間の内積で求まる
				// このハーフベクトルとは視線方向と光源の間のベクトルを正規化したものである
				// viewDir (視線方向)と _WorldSpaceLightPos0 (光源) のベクトルをたしあわせて normalize (正規化) することでハーフベクトルを求め
				// normal (表面の法線) と halfVector の dot (内積)を取る

				float3 halfVector = normalize(_WorldSpaceLightPos0 + viewDir);
				float NdotH = dot(normal, halfVector);

				// pow 関数で鏡面反射のサイズを制御する
				// NdotH (鏡面反射の強さ) に DirectionalLight で照らされてる時は 1, 影は 0 となる lightIntensity を掛け合わせることで
				// 照らされている部分にのみハイライトが入る（影にハイライトが入らない）ようにしている
				// _Glossiness が乗算している理由はよくわかっていないが
				// マテリアルの値が小さいほど大きな効果が得られ、シェーダーでの作業が容易になるように制御しているらしい

				float specularIntensity = pow(NdotH * lightIntensity, _Glossiness * _Glossiness);

				// 上記の specularIntensity だとリアルなレンダリングになってしまうのでハイライトもトゥーン化するために
				// smoothstep 関数を使ってなるべく2階調を保ちつつ、境界となる値が 0.005-0.01 の部分をグラデーションして馴染ませる
				// 最後に _SpecularColor で設定したハイライトの色を反映する

				float specularIntensitySmooth = smoothstep(0.005, 0.01, specularIntensity);
				float4 specular = specularIntensitySmooth * _SpecularColor;				

				// エッジを縁取るための RimLighting
				// オブジェクトのリムはカメラから離れた面として定義されるため
				// 法線とビュー方向の内積を取って反転させる必要がある

				float rimDot = 1 - dot(viewDir, normal);

				// この処理がないとハイライトのある方向に最小限のリムしか表示されず影の近くまでリムが届かない（光源に近い側に照りみたいなリムしか入らない）
				// そこで閾値を掛け合わせることでリムを影の直前まで伸ばす
				// なぜ pow を使うと 0 のとき強調されて、1 のときに小さくなる（サーフェスに近い場所だけリムが入る）のかはわかっていない

				float rimIntensity = rimDot * pow(NdotL, _RimThreshold);

				// リム(縁取り)も _RimAmount の量に合わせてトゥーン化して設定した _RimColor の色味で表現する

				rimIntensity = smoothstep(_RimAmount - 0.01, _RimAmount + 0.01, rimIntensity);
				float4 rim = rimIntensity * _RimColor;

				// サンプリング対象のテクスチャ座標に対して
				// _MainTex で設定したテクスチャを反映する
				// _Color * sample だと設定したテクスチャに _Color で設定した色だけをつけて反映する
				// そこには影も何もない

				float4 sample = tex2D(_MainTex, i.uv);

				// _AmbientColor は影の色味を追加する要素。black であれば黒い影を。 white であれば白い影を落とす

				return (light + _AmbientColor + specular + rim) * _Color * sample;
			}
			ENDCG
		}

		// 影を落として受け取る機能
		// 勘違いしがちだが、このシェーダーを付与したオブジェクトが落とす影ではない
		// このシェーダーを持つオブジェクトが何かの影になった際に影をこのオブジェクトにつけるための仕組みだ
		// シェーダーは光源の反射を計算すると重いので
		// フラグメントシェーダーが受け取る様々なベクトルから
		// 影となる位置にいると判断される場合に光源の色とそのオブジェクトが影として落とす色から影を表現する
		// それを表現するための標準シェーダーを UsePass を使って流用する

        UsePass "Legacy Shaders/VertexLit/SHADOWCASTER"
	}

	// 参考文献
	// ※1 Unity Toon Shader Tutorial - Roystan | https://roystan.net/articles/toon-shader.html
	// ※2 Unityシェーダープログラミングの教科書 ShaderLab言語解説編
	// ※3 HLSL のシェーダーキーワードの宣言と使用 | https://docs.unity3d.com/ja/current/Manual/SL-MultipleProgramVariants.html
}
