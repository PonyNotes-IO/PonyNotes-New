import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/splash_bloc.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/user/domain/auth_state.dart';
import 'package:appflowy/user/presentation/helpers/helpers.dart';
import 'package:appflowy/user/presentation/router.dart';
import 'package:appflowy/user/presentation/screens/screens.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/phone_bind_screen.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:flowy_infra/platform_extension.dart';

class SplashScreen extends StatefulWidget {
  /// Root Page of the app.
  const SplashScreen({super.key, required this.isAnon});

  final bool isAnon;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _hasHandledAuth = false; // 防止重复处理
  bool _privacyPromptShown = false;

  static const _privacyAcceptedKey = 'privacy_policy_accepted';
  static const _privacyPolicy = '''欢迎你使用“小马笔记”（以下简称“本产品”）的产品与/或服务！
我们（指北京爱欧爱科技有限公司及其关联公司）深知用户个人隐私及信息的重要性，并非常重视用户（以下简称“你”）的隐私和个人信息保护。我们将按照法律法规的要求，采取相应的措施保护你个人信息的安全可控。基于前述的理念和目的，我们制定《小马笔记隐私政策》（以下简称“本隐私政策”）并对你做出如下提示：
本隐私政策适用于“小马笔记”提供的所有产品和服务，你在使用我们的产品与/或服务时，我们可能会收集和使用你的个人信息。我们希望通过本隐私政策向你说明我们在提供产品与/或服务时如何收集、使用、保存、共享和转让你的个人信息、你享有的个人信息用户权利以及我们如何保障你的个人信息安全。
请你在使用我们的产品与/或服务前仔细阅读，确认你已经充分知悉并理解本隐私政策内容，并可根据本隐私政策的指引作出你认为适当的选择。一旦你开始使用或在我们更新本隐私政策后继续使用我们的产品与/或服务，即表示你已充分理解并同意本政策（含更新版本）内容，并且同意我们按照隐私政策收集、使用、保存和共享你的相关信息。
本隐私政策所适用的产品和服务由北京爱欧爱科技有限公司及其关联公司运营，公司注册地址为北京市海淀区中关村大街18号8层04-113
目录
一、我们如何收集和使用你的个人信息
二、我们如何使用Cookie和同类技术
三、我们如何共享、转让、共开披露你的个人信息
四、第三方SDK使用说明
五、我们如何保护和保存你的个人信息
六、你的权利
七、未成年人信息的保护
八、通知和修订
九、如何联系我们
一、我们如何收集和使用你的个人信息
当你使用小马笔记中的 AI 辅助功能（包括但不限于内容总结、改写、问答等）时，我们可能会将你主动提交或由你触发处理的内容（包括文本及其结构化结果），通过安全加密的方式发送至第三方人工智能服务提供商进行处理。
我们使用的人工智能服务由阿里云等国内合规的云服务商提供，仅用于完成你当前请求的处理，不会将你的内容用于模型训练或其他与你请求无关的用途，除非另行取得你的明确授权。
我们不会主动向人工智能服务提供商提供你的身份信息。
该等人工智能处理仅限于实现你所选择并触发的具体 AI 功能，不用于用户画像、个性化推荐、自动化决策或其他与当前请求无关的用途。
我们会根据合法正当、最小必要、公开透明的原则，基于本隐私政策所述的目的，收集和使用你的个人信息。
为提升你的信息检索与使用效率，我们可能在你的设备或服务器侧，对你在小马笔记中存储的内容进行技术性处理，包括但不限于内容拆分、结构化整理、索引构建及相似性匹配。
上述处理仅用于在你发起请求时，帮助你更高效地检索和使用你自身已存储的内容，不会改变你对该等内容的控制权，也不会用于与提供服务无关的其他目的。
在你使用我们的产品及/或服务时，我们需要/可能需要收集和使用的你的个人信息包括如下两种：
为了向你提供服务，我们会按照如下方式收集、使用你的个人信息：
（一）使用我们产品和服务所必须的功能
1.帐号的注册、登录
（1）当你首次注册“小马笔记”账号时，你需要提供手机号码完成注册，创建账号。手机号码是你注册“小马笔记”账号所必须，若你拒绝提供此信息，将无法注册“小马笔记”账户。
（2）当你使用微信关联登录“小马笔记”时，我们会收集你的个人电话号码、微信头像、昵称，此种情况下，你的个人电话号码即成为你的“小马笔记”账号，你可以通过所关联的微信或输入个人电话号码及我们发送的手机验证码登录“小马笔记”。
2．使用笔记同步、笔记记录、笔记优化、查询搜索服务时：我们会收集你提供的内容，包括你自定义输入的文本、图片、语音及其形成的信息，我们收集这些信息是为了根据你的表达向你提供笔记同步、笔记记录、笔记优化、查询搜索服务。如你上传的信息中涉及你的个人信息，未经你的授权同意，我们不会向其他第三方公司、组织和个人共享、转让、披露，请你知悉。
3．客服与售后功能：当你与我们联系或提出咨询、争议纠纷处理申请时，我们需要你提供必要的个人信息以核验你的用户身份，我们可能会保存你的通信/通话记录和相关内容或你留下的联系方式等信息，以便与你取得联系或帮助你解决/定位问题，或记录相关问题的处理方式及结果。为了向你提供服务及改进服务质量的合理需要，我们可能会使用的你的手机号码及你与客服联系时你提供的相关信息。
（二）向你提供产品或服务
当你使用“小马笔记”服务时，为了维护我们服务的正常运行，改进及优化我们的服务体验以及保障你的账号安全，我们会收集你的下述信息：
1．设备信息：我们会根据你在使用产品中授予的具体权限，接受并记录你所使用的设备相关信息（包括设备型号、操作系统版本、IP地址、软件版本号等软硬件特征信息），同时，我们会基于提供更便捷、更优质的服务和体验，收集你的某些设备权限：
（1）基于麦克风的权限：你可以通过开启麦克风权限以实现语音输入、语音转文字的功能。
（2）基于相册（仅写入）权限：当你保存笔记海报时，我们将在获取你的明确同意后，使用你的相册（仅写入）权限。
（3）基于剪贴板的权限：当你在小马笔记中复制、粘贴、剪切信息时，我们将在设备本地访问你剪切板中的内容，我们不会上传您剪切板中的内容至我们的服务器。
请你知悉获取上述权限的前提条件是你在你的设备中已允许开启麦克风访问权限、存储权限以实现这些权限所涉及信息的收集和使用。你可以在你的设备的设置/应用权限中查看上述权限的状态，并可根据需要选择开启或关闭相应的权限。请你注意，你开启这些权限即代表你授权我们可以收集和使用这些个人信息来实现上述的功能，你关闭权限即代表你取消了这些授权，我们将不再继续收集和使用你的这些个人信息，也无法为你提供上述与这些授权所对应的功能。你关闭权限的决定不会影响此前基于你的授权所进行的信息收集及使用。
2．日志信息：我们会收集你对我们服务的详细使用情况，作为有关日志保存，包括操作日志、服务日志信息。
3．第三方账号信息：基于你选择使用的“小马笔记”服务，我们可能从关联方、第三方合作伙伴获取你授权共享的相关信息，例如，当你使用笔记同步功能时，我们将根据你的授权，获取你在第三方账号下的相关信息（包括：用户名、手机号、最近一次登录时间），并在你同意本政策后将你的第三方帐号与“小马笔记”帐号绑定。
（三）授权同意的除外
请你理解，根据相关法律法规的要求，以下情形中，我们收集、使用你的个人信息无需征得你的授权同意：
（1）与个人信息控制者履行法律法规规定的义务相关的；
（2）与国家安全、国防安全直接相关的；
（3）与公共安全、公共卫生、重大公共利益直接相关的；
（4）与刑事侦查、起诉、审判和判决执行等直接相关的；
（5）出于维护个人信息主体或其他个人的生命、财产等重大合法权益但又很难得到本人授权同意的；
（6）所涉及的个人信息是个人信息主体自行向社会公众公开的；
（7）根据个人信息主体要求签订和履行合同所必需的；
（8）从合法公开披露的信息中收集个人信息的，如合法的新闻报道、政府信息公开等渠道；
（9）维护所提供产品或服务的安全稳定运营所必需的，例如发现、处置产品或服务的故障。
（10）个人信息控制者为学术研究机构，出于公共利益开展统计或学术研究所必要，且其对外提供学术研究或描述的结果时，对结果中所包含的个人信息进行去标识化处理的。
特别提示您注意，如信息无法单独或结合其他信息识别到您的个人身份，其不属于法律意义上您的个人信息；当您的信息可以单独或结合其他信息识别到您的个人身份时或我们将无法与任何特定个人信息建立联系的数据与其他您的个人信息结合使用时，这些信息在结合使用期间，将作为您的个人信息按照本政策处理与保护。
二、我们如何使用 Cookie
1．为使你获得更轻松的访问体验，我们可能会通过采用各种技术收集和存储你访问“小马笔记”产品和服务时的相关数据，在你访问或再次访问“小马笔记”产品和服务时，我们能识别你的身份，并通过分析数据为你提供更好更多的服务。包括在你的移动设备上发送一个或多个名为Cookies的小数据文件，指定给你的Cookies 是唯一的，它只能被将Cookies发布给你的域中的Web服务器读取。我们向你发送Cookies是为了简化你重复登录的步骤、帮助判断你的登录状态以及帐号或数据安全。
2．我们不会将 Cookies 用于本隐私政策所述目的之外的任何用途。你可根据自己的偏好管理或删除 Cookies，你可以也可以清除软件内保存的所有Cookies。
三、我们如何共享、转让、公开披露您的个人信息
（一）共享
我们非常重视保护你的个人信息。未经你的授权同意,我们不会与其他第三方公司、组织和个人共享你的个人信息，除非是匿名化或去标识化处理后的无法识别或关联到你的信息，且共享第三方无法重新识别此类信息的自然人主体。我们仅会出于合法、正当、必要、特定、明确的目的共享你的个人信息，并且只会共享必要的个人信息。如果我们共享你的个人敏感信息,我们会将再次征求你的授权同意。如果第三方改变或超越你原授权同意范围使用你的个人信息，则我们会要求第三方再次征得您的授权同意。
1.我们不会与第三方公司、组织和个人共享你的个人信息，但以下情况除外：
1．为实现我们的服务/功能所必需进行的共享：
在某些情况下，为向你提供我们的服务或实现我们的产品与/或服务的业务功能，我们必须共享你的个人信息，才能实现我们的产品与/或服务的核心功能或提供你需要的服务，例如：为我们的产品与/或服务提供功能支持的服务提供商；我们接受尽职调查或审计时，与外部监管、专业咨询机构(如审计机构)等共享你的相关信息，包括在你使用 AI 辅助功能时，为完成你主动发起的请求，将你提交的相关内容提供给人工智能服务提供商进行处理。
2．实现安全与分析统计的共享信息
（1）保障使用安全：我们非常重视账号与服务安全，为保障你和其他用户的账号与财产安全,使你和我们的正当合法权益免受不法侵害，我们和关联公司或服务提供商可能会共享必要的设备、账号及日志信息。
（2）分析产品使用情况：为分析我们服务的使用情况,提升用户使用的体验,可能会与关联方或第三方共享产品使用情况(崩溃、闪退)的统计性数据，这些数据难以与其他信息结合识别你的个人身份。
3．第三方SDK类服务商：为保障我们的稳定运行、功能实现，使你能够使用和享受更多的服务及功能,我们会嵌入业务合作伙伴的SDK或其他类似的应用程序。我们会对业务合作伙伴获取信息的软件工具开发包(SDK)、应用程序接口(API)进行严格的安全监测，令其按照本政策以及其他任何相关的保密和安全措施来处理个人信息，以保护数据安全。用户点击'同意'前，我们或SDK不和云端有任何数据交互、我们或SDK不对设备进行任何数据读取，用户同意《隐私政策》后再初始化SDK采数。
4．其他情况
（一）共享我们不会与第三方公司、组织和个人共享你的个人信息，但以下情况除外：（1）事先获得你明确的同意或授权；(2）根据适用的法律法规、法律程序的要求、强制性的行政或司法要求所必须的情况下进行提供；（3）在法律法规允许的范围内，为维护你、其他得到用户或我们的正当利益或安全免遭损害而有必要提供；（4）只有共享你的信息，才能实现我们的产品与/或服务的核心功能或提供你需要的服务；（5）应你需求为你处理你与他人的纠纷或争议；（6）符合与你签署的相关协议（包括在线签署的电子协议以及相应的规则）或其他的法律文件约定所提供；（7）基于符合法律法规的社会公共利益而使用。（二）转让我们不会将你的个人信息转让给任何公司、组织和个人，但以下情况除外：（1）事先获得你明确的同意或授权；（2）根据适用的法律法规、法律程序的要求、强制性的行政或司法要求所必须的情况进行提供；（3）符合与你签署的相关协议（包括在线签署的电子协议以及相应的平台规则）或其他的法律文件约定所提供；（4）在涉及合并、收购、资产转让或类似的交易时，如涉及到个人信息转让，我们会要求新的持有你个人信息的公司、组织继续受本隐私政策的约束，否则,我们将要求该公司、组织重新向你征求授权同意。（三）公开披露我们仅在以下情况，才会公开披露你的个人信息：（1）根据你的需求，在你明确同意的披露方式下披露你所指定的个人信息；（2）根据法律、法规的要求、强制性的行政执法或司法要求所必须提供你个人信息的情况下，我们可能会依据所要求的个人信息类型和披露方式公开披露你的个人信息。在符合法律法规的前提下，当我们收到上述披露信息的请求时，我们会要求必须出具与之相应的法律文件，如传票或调查函。我们坚信，对于要求我们提供的信息，应该在法律允许的范围内尽可能保持透明。我们对所有的请求都进行了慎重的审查，以确保其具备合法依据，且仅限于执法部门因特定调查目的且有合法权利获取的数据。在法律法规许可的前提下，我们披露的文件均在加密密钥的保护之下。（四）例外情形以下情形中，共享、转让、公开披露你的个人信息无需事先征得你的授权同意：（1）与个人信息控制者履行法律法规规定的义务相关的；（2）与国家安全、国防安全直接相关的；（3）与公共安全、公共卫生、重大公共利益直接相关的；（4）与刑事侦查、起诉、审判和判决执行等直接相关的；（5）出于维护你或其他个人的生命、财产等重大合法权益但又很难得到本人授权同意的；（6）所涉及的个人信息是你自行向社会公众公开的；（7）根据个人信息主体要求签订和履行合同所必需的；（8）从合法公开披露的信息中收集个人信息的，如合法的新闻报道、政府信息公开等渠道；
四、第三方SDK使用情况
（一）1. SDK名称：APP支付客户端SDK
2.开发者:支付宝(杭州)信息技术有限公司
3.SDK隐私政策链接：https://opendocs.alipay.com/open/54/01g6qm#%E6%94%AF%E4%BB%98%E5% AE%9D%20App%20%E6%94%AF%E4%BB%98%E5%AE%A2%E6%88%B7%E7%AB%AF%20SDK%20%E9%9A%90%E7%A7%81%E6%94%BF%E7%AD%96
（二）1. SDK名称：微信OpenSDK Android
2.开发者:深圳市腾讯计算机系统有限公司
3.SDK隐私政策链接：https://support.weixin.qq.com/cgi-bin/mmsupportacctnodeweb-bin/pages/RYiYJkLOrQwu0nb8
（三）1. SDK名称：抖音openSDK（安卓版）
2.开发者:北京微播视界科技有限公司
3.SDK隐私政策链接：https://developer.open-douyin.com/docs/resource/zh-CN/dop/operation-standard/service-protocol/douyinsdk_pingtaiyinsizhengce
五、我们如何保护和保存你的个人信息
（一）个人信息的保存
1．我们依照法律法规的规定，将在中华人民共和国境内运营过程中收集和产生的你的个人信息存储于境内。我们不会将上述信息传输至境外，除非适用的法律有明确规定或者获得你的明确授权。
2．我们在法律法规规定的期限内或为你提供满足得到产品与/或服务目的所必需且最短的期限内保存你的个人信息。在超出保留期间后，我们会根据适用法律的要求删除或匿名化处理你的个人信息。
（二）个人信息的保护
1．我们一直都极为重视保护用户的个人信息安全，为此我们采用了符合行业标准的安全技术措施及组织和管理措施等保护措施以最大程度降低你的信息被泄露、毁损、误用、非授权访问、非授权披露和更改的风险。
2．我们会采取符合业界标准的合理可行的安全措施和技术手段存储和保护你的个人信息，以防止您信息丢失、遭到被未经授权的访问、公开披露、使用、修改、毁损、丢失或泄漏。我们会采取一切合理可行的措施，保护你的个人信息。我们会使用加密技术确保数据的保密性，我们会使用受信赖的保护机制防止数据遭到恶意攻击。
3．我们会建立专门的管理制度、流程和组织确保信息安全。例如，我们严格限制访问信息的人员范围，要求他们遵守保密义务，并进行审查。
4．在不幸发生个人隐私数据泄露事件后，我们将按照法律法规的要求，及时向你告知：安全事件的基本情况和可能的影响、我们已采取或将要采取的处置措施、你可自主防范和降低风险的建议、对你的补救措施等。我们将及时将事件相关情况以邮件、信函、电话、推送通知等方式告知你，难以逐一告知个人信息主体时，我们会采取合理、有效的方式发布公告。同时，我们还将按照监管部门要求，主动上报个人信息安全事件的处置情况。
六、你的权利
（一）访问你的个人信息
1．你有权查询你的信息，你可以通过小程序点击“我的”在对应页面内查询你的信息。或通过网页版左下角头像图标查看个人信息。
（二）删除你的个人信息
1．在以下情形中，你可以向我们提出删除个人信息的请求：
（1）如果我们处理个人信息的行为违反法律法规；
（2）如果我们收集、使用你的个人信息，却未征得你的同意；
（3）如果我们处理个人信息的行为违反了与你的约定；
（4）如果你不再使用我们的产品或服务，或你注销了帐号；
（5）如果我们不再为你提供产品或服务。
（三）注销你的帐号
1．如果你希望终止我们的服务时，你可以通过访问小程序“我的”或访问网页版左下角头像图标，联系我们的人工客服，申请注销你的账户。
2．在你注销账号后，你将无法再以此账号登录和使用我们的产品与服务，该账号在我们的产品与服务使用期间已产生的但未消耗完毕的权益及未来的预期利益等全部权益将被清除；该账号下的内容、信息、数据、记录等将会被删除或匿名化处理(但法律法规另有规定或监管部门另有要求的除外)；同时,账号一旦注销完成，将无法恢复。
七、未成年人的个人信息保护
我们非常重视对未成年人个人信息的保护。“小马笔记”产品主要面向成年人，若你是不满十八周岁的未成年人，在使用我们的产品与/或服务前，应事先取得你的监护人的同意。
特别地，若你是不满十六周岁的未成年人的监护人，在你的被监护人使用我们的产品及相关服务前，你应为其阅读并同意本隐私政策。
我们根据国家相关法律法规的规定保护未成年人的个人信息，只会在法律允许、监护人明确同意或保护未成年人所必要的情况下收集、使用、共享或披露未成年人的个人信息。
如果我们发现自己在未事先获得可证实的父母或法定监护人单独同意的情况下收集了未成年人的个人信息，则会设法尽快删除相关数据。
若你是未成年人的监护人，当你对你所监护的未成年人的个人信息有相关疑问时，请通过本隐私政策公示的联系方式与我们联系。
八、通知和修订
1．为给你提供更好的服务，我们可能会根据服务更新的情况及法律法规的相关要求随之更新本隐私政策。我们会在本页面内公布对隐私政策作出的任何变更。
对于重大变更，我们还会提供更为显著的通知（包括网站公告、推送通知、弹窗提示或其他方式）说明隐私政策的具体变更内容。
本隐私政策所指的重大变更包括但不限于：
（1）我们的服务模式发生重大变化。如处理个人信息的目的、处理的个人信息类型、个人信息的使用方式等；
（2）我们在业务调整、破产并购等引起的所有者变更等；
（3）个人信息共享、转让或公开披露的主要对象发生变化；
（4）你参与个人信息处理方面的权利及其行使方式发生重大变化。
如果你不同意该等变更，可以选择停止使用“小马笔记”服务；如你仍然继续使用我们的服务，即表示你已充分阅读、理解并同意受经修订的本政策的约束。
九、联系我们
1．如果你认为你的个人信息权利可能受到侵害，或者发现侵害个人信息权利的线索，你可以通过通过发送邮件至support@xiaomabiji.com联系我们进行投诉、举报，我们核查后会在十五个工作日内反馈你的投诉与举报。
2．我们设立了专门的个人信息保护负责人，如你对本隐私政策或你个人信息的相关事宜有任何问题、意见或建议，可以通过发送邮件至support@xiaomabiji.com与我们联系，我们会在十五个工作日内对你提出的问题、意见或建议进行回复或处理。
本隐私政策发布日期：2026年2月14日
本隐私政策生效日期：2026年2月14日
''';

  @override
  Widget build(BuildContext context) {
    if (widget.isAnon) {
      return FutureBuilder<void>(
        future: _registerIfNeeded(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          return _buildChild(context);
        },
      );
    } else {
      return _buildChild(context);
    }
  }

  BlocProvider<SplashBloc> _buildChild(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          getIt<SplashBloc>()..add(const SplashEvent.getUser()),
      child: Scaffold(
        body: BlocListener<SplashBloc, SplashState>(
          listenWhen: (previous, current) {
            // 只在状态变化时触发，但确保 authenticated 状态会被处理
            return previous.auth != current.auth;
          },
          listener: (context, state) {
            if (_hasHandledAuth) {
              return;
            }
            state.auth.map(
              authenticated: (r) {
                _hasHandledAuth = true;
                _handleAuthenticated(context, r);
              },
              unauthenticated: (r) {
                _hasHandledAuth = true;
                _handleUnauthenticated(context, r);
              },
              initial: (r) {},
            );
          },
          child: BlocBuilder<SplashBloc, SplashState>(
            builder: (context, state) {
              // 在首次 build 时也检查状态（如果已经是 authenticated）
              if (!_hasHandledAuth) {
                state.auth.map(
                  authenticated: (r) {
                    // 使用 WidgetsBinding.instance.addPostFrameCallback 确保在 build 完成后执行
                    // 只执行一次，避免重复调用
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      // 检查是否已经处理过（通过检查 context 是否仍然 mounted）
                      if (mounted && !_hasHandledAuth) {
                        _hasHandledAuth = true;
                        _handleAuthenticated(context, r);
                      }
                    });
                  },
                  unauthenticated: (r) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_hasHandledAuth) {
                        _hasHandledAuth = true;
                        _handleUnauthenticated(context, r);
                      }
                    });
                  },
                  initial: (r) {},
                );
              }
              return const Body();
            },
          ),
        ),
      ),
    );
  }

  /// 检查 tempUserSave 字段
  Future<bool> _checkTempUserSave() async {
    try {
      Log.info('🔵 [SplashScreen] 开始检查 tempUserSave 字段');
      // 直接使用 SharedPreferences 读取，不通过 TempUserCache
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString('tempUserSave');
      Log.info('🔵 [SplashScreen] 直接读取 tempUserSave 值: $value');
      final tempUserSave = value == 'true';
      Log.info('🔵 [SplashScreen] tempUserSave 结果: $tempUserSave');
      // 不再在这里清除字段，而是在登录成功后清除
      return tempUserSave;
    } catch (e, stack) {
      Log.error('🔵 [SplashScreen] 检查 tempUserSave 字段失败: $e', stack);
      return false;
    }
  }

  Future<void> _registerIfNeeded() async {
    final result = await UserEventGetUserProfile().send();
    if (result.isFailure) {
      await getIt<AuthService>().signUpAsGuest();
    }
  }

  /// Handles the authentication flow once a user is authenticated.
  Future<void> _handleAuthenticated(
    BuildContext context,
    Authenticated authenticated,
  ) async {
    if (UniversalPlatform.isAndroid) {
      final firstConsent = await _showPrivacyPolicyIfNeeded(context);
      if (firstConsent == null) return;
      if (firstConsent) {
        context.go(SignInScreen.routeName);
        return;
      }
    }
    // 检查用户是否需要绑定手机号（第三方登录但未绑定手机号）
    // 必须在进入主界面之前检查
    if (isAppFlowyCloudEnabled) {
      try {
        final profileResult = await UserBackendService.getCurrentUserProfile();
        final profile = profileResult.fold(
          (profile) => profile,
          (error) {
            Log.error(
                '[SplashScreen] Failed to get user profile: ${error.msg}');
            return null;
          },
        );

        if (profile != null) {
          // 检查是否需要绑定手机号
          final needBindPhone = _needBindPhone(profile.phone);

          if (needBindPhone) {
            // 用户需要绑定手机号，跳转到绑定手机号页面
            // 使用同步方式，确保在进入主界面之前执行
            final rootContext = AppGlobals.rootNavKey.currentState?.context;
            if (rootContext != null && rootContext.mounted) {
              Navigator.of(rootContext, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (context) => const PhoneBindScreen(
                    logoutOnBack: true,
                  ),
                ),
              );
              // 不进入主界面
              return;
            } else {
              Log.error(
                  '[SplashScreen] Root context not available for PhoneBindScreen navigation');
              // 如果 context 不可用，退出登录并重启应用
              try {
                await getIt<AuthService>().signOut();
                await runAppFlowy();
              } catch (e, stack) {
                Log.error('[SplashScreen] Failed to sign out: $e', stack);
              }
              return;
            }
          }
        }
      } catch (e, stack) {
        Log.error('[SplashScreen] Error checking phone binding: $e', stack);
        // 如果检查失败，继续正常流程
      }
    }

    // 🔧 修复登录后卡住问题：添加重试逻辑，等待 Folder 初始化完成
    // 原因：runAppFlowy() 重新初始化应用时，Folder 可能还未完全初始化
    int retryCount = 0;
    const maxRetries = 30; // 最多等待15秒（每次500ms），慢机器上需要更长时间
    const retryDelay = Duration(milliseconds: 500);

    while (retryCount < maxRetries) {
      final result = await FolderEventGetCurrentWorkspaceSetting().send();

      final success = result.fold(
        (workspaceSetting) {
          // After login, replace Splash screen by corresponding home screen
          getIt<SplashRouter>().goHomeScreen(
            context,
          );
          return true;
        },
        (error) {
          // 如果是 "Folder not initialized" 错误，继续重试
          if (error.msg.contains('Folder not initialized') &&
              retryCount < maxRetries - 1) {
            return false;
          }
          // 其他错误或重试次数耗尽，显示错误
          handleOpenWorkspaceError(context, error);
          return true;
        },
      );

      if (success) {
        break;
      }

      retryCount++;
      await Future.delayed(retryDelay);
    }
  }

  // 检查是否需要绑定手机号
  // 只有第三方登录（微信、抖音）的用户才有临时手机号（+86temp...），需要绑定
  // 邮箱注册的用户手机号为空，不需要绑定
  // 手机号注册的用户有正常手机号，不需要绑定
  bool _needBindPhone(String? phone) {
    if (phone == null || phone.isEmpty) {
      return false;
    }
    // 只有临时手机号（第三方登录）才需要绑定
    return phone.startsWith('+86temp');
  }

  Future<void> _handleUnauthenticated(
    BuildContext context,
    Unauthenticated result,
  ) async {
    if (UniversalPlatform.isAndroid) {
      final consent = await _showPrivacyPolicyIfNeeded(context);
      if (consent == null) return;
    }
    // replace Splash screen as root page
    if (isAuthEnabled || PlatformInfo.isMobile) {
      context.go(SignInScreen.routeName);
    } else {
      // if the env is not configured, we will skip to the 'skip login screen'.
      context.go(SkipLogInScreen.routeName);
    }
  }

  /// Returns true when this launch just accepted the policy, false when it was
  /// already accepted, and null after the user declined and the app closed.
  Future<bool?> _showPrivacyPolicyIfNeeded(BuildContext context) async {
    if (_privacyPromptShown) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_privacyAcceptedKey) == true) return false;
    _privacyPromptShown = true;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final foreground = isDark ? Colors.white : Colors.black;
        final surface = isDark ? const Color(0xFF202124) : Colors.white;
        const ponyOrange = Color(0xFFFF3D0A);
        return AlertDialog(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
          title: Text(
            '隐私条款',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          content: Container(
            constraints: const BoxConstraints(maxHeight: 320),
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF17181B) : const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              child: Text(
                _privacyPolicy,
                style: TextStyle(
                  color: foreground,
                  height: 1.45,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          actions: [
            SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: ponyOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text(
                        '同意',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? Colors.white38 : Colors.black26,
                      minimumSize: const Size.fromHeight(34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text(
                      '不同意',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (accepted == true) {
      await prefs.setBool(_privacyAcceptedKey, true);
      return true;
    }
    await SystemNavigator.pop();
    return null;
  }
}

class Body extends StatelessWidget {
  const Body({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      child: PlatformInfo.isMobile
          ? const _MobileSplashBody()
          : const _DesktopSplashBody(),
    );
  }
}

class _DesktopSplashBody extends StatelessWidget {
  const _DesktopSplashBody();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return SingleChildScrollView(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image(
            fit: BoxFit.cover,
            width: size.width,
            height: size.height,
            image: const AssetImage(
              'assets/images/appflowy_launch_splash.jpg',
            ),
          ),
          const CircularProgressIndicator.adaptive(),
        ],
      ),
    );
  }
}

class _MobileSplashBody extends StatelessWidget {
  const _MobileSplashBody();

  String _launchAsset(BuildContext context, {required bool isDark}) {
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.shortestSide >= 600;
    if (isTablet) {
      return isDark
          ? 'assets/images/launch_screen_tablet_dark.png'
          : 'assets/images/launch_screen_tablet_light.png';
    }
    return isDark
        ? 'assets/images/launch_screen_dark.png'
        : 'assets/images/launch_screen_light.png';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox.expand(
      child: Image.asset(
        _launchAsset(context, isDark: isDark),
        fit: BoxFit.cover,
      ),
    );
  }
}
