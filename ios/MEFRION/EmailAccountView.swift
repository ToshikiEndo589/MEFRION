import SwiftUI

enum SignupRequirements {
    static func validEmail(_ email:String)->Bool {
        let address=email.trimmingCharacters(in:.whitespacesAndNewlines)
        let parts=address.split(separator:"@",omittingEmptySubsequences:false)
        return parts.count==2 && !parts[0].isEmpty && parts[1].contains(".") && !address.contains(" ")
    }

    static func valid(email:String,password:String,confirmation:String,adult:Bool,confirmed:Bool)->Bool {
        validEmail(email) && password.count>=12 && password==confirmation && adult && confirmed
    }
}

struct EmailAccountView:View {
    @ObservedObject var client:CloudFamilyClient
    @Environment(\.dismiss) private var dismiss
    @State private var mode="login"
    @State private var email=""
    @State private var password=""
    @State private var passwordConfirmation=""
    @State private var adult=false
    @State private var confirmed=false
    @State private var code=""
    @State private var awaitingEmail=false
    @State private var passwordChanged=false
    @State private var notice:String?

    init(client:CloudFamilyClient,initialMode:String="login") {
        self.client=client
        _mode=State(initialValue:initialMode)
    }

    private var address:String {email.trimmingCharacters(in:.whitespacesAndNewlines)}
    private var canSubmit:Bool {
        guard !client.busy,SignupRequirements.validEmail(address) else{return false}
        switch mode {
        case "signup":return SignupRequirements.valid(email:address,password:password,confirmation:passwordConfirmation,adult:adult,confirmed:confirmed)
        case "login":return !password.isEmpty
        default:return true
        }
    }

    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                header
                if client.authenticated && mode != "recovery" {completedCard}
                else if mode=="signup" && awaitingEmail {verificationCard(recovery:false)}
                else if mode=="recovery" && passwordChanged {resetCompletedCard}
                else if mode=="recovery" && client.authenticated && awaitingEmail {newPasswordCard}
                else if mode=="recovery" && awaitingEmail {verificationCard(recovery:true)}
                else {
                    if mode != "recovery" {modePicker}
                    credentialsCard
                }
                if client.busy {ProgressView().frame(maxWidth:.infinity)}
                if let notice {Text(notice).font(.footnote).foregroundStyle(Theme.actionText).frame(maxWidth:.infinity,alignment:.leading)}
                if let error=client.error {Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("account-error")}
            }
            .padding(.horizontal,20)
            .padding(.vertical,12)
            .frame(maxWidth:520)
            .frame(maxWidth:.infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("アカウント")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of:mode) {_,_ in password="";passwordConfirmation="";code="";awaitingEmail=false;passwordChanged=false;notice=nil}
        .protectWhenInactive()
    }

    private var header:some View {
        VStack(alignment:.leading,spacing:5) {
            Text(client.authenticated && mode != "recovery" ? (mode=="signup" ? "登録できたよ" : "おかえりなさい") :
                 mode=="signup" ? (awaitingEmail ? "メールをチェック" : "はじめよう 🐾") :
                 mode=="recovery" ? (awaitingEmail ? "メールをチェック" : "パスワードを忘れたら") : "おかえりなさい")
                .font(.system(size:26,weight:.bold,design:.rounded))
                .foregroundStyle(Theme.text)
            Text(client.authenticated && mode != "recovery" ? "好きな子を見つけに行こう。" :
                 mode=="signup" ? (awaitingEmail ? "届いたコードを入れるだけ。" : "犬猫を飼っていなくても、見るだけでも大歓迎。") :
                 mode=="recovery" ? "メールからアカウントを確認します。" : "いつものメールでログイン。")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .padding(.top,2)
    }

    private var modePicker:some View {
        HStack(spacing:4) {
            modeButton("新規登録",value:"signup")
            modeButton("ログイン",value:"login")
        }
        .padding(4)
        .background(Theme.accent.opacity(0.09),in:Capsule())
    }

    private func modeButton(_ title:String,value:String)->some View {
        Button(title) {mode=value}
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(mode==value ? Theme.actionText : Theme.secondaryText)
            .frame(maxWidth:.infinity,minHeight:42)
            .background(mode==value ? Color.white : Color.clear,in:Capsule())
            .accessibilityAddTraits(mode==value ? .isSelected : [])
    }

    private var credentialsCard:some View {
        VStack(alignment:.leading,spacing:12) {
            TextField("メールアドレス",text:$email)
                .textContentType(.emailAddress).textInputAutocapitalization(.never)
                .autocorrectionDisabled().keyboardType(.emailAddress)
                .textFieldStyle(AuthInputStyle()).accessibilityLabel("メールアドレス").accessibilityIdentifier("account-email")

            if mode != "recovery" {
                SecureField(mode=="signup" ? "パスワード（12文字以上）" : "パスワード",text:$password)
                    .textContentType(mode=="signup" ? .newPassword : .password)
                    .textFieldStyle(AuthInputStyle()).accessibilityLabel("パスワード").accessibilityIdentifier("account-password")
            }

            if mode=="signup" {
                SecureField("パスワードをもう一度",text:$passwordConfirmation)
                    .textContentType(.newPassword)
                    .textFieldStyle(AuthInputStyle()).accessibilityIdentifier("account-password-confirmation")
                if !passwordConfirmation.isEmpty && password != passwordConfirmation {
                    Text("パスワードが一致しません").font(.caption).foregroundStyle(.red)
                }
                Toggle("18歳以上です",isOn:$adult).tint(Theme.accent).font(.subheadline)
                Toggle("データの取り扱いを確認しました",isOn:$confirmed).tint(Theme.accent).font(.subheadline)
                NavigationLink("データの取り扱いを見る") {PrivacyInformationView()}
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.actionText)
            }

            Button(mode=="signup" ? "確認メールを送る" : mode=="recovery" ? "復旧メールを送る" : "ログイン") {submit()}
                .frame(maxWidth:.infinity)
                .buttonStyle(CoralButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.45)
                .accessibilityIdentifier("account-submit")

            if mode=="signup" {
                Button("すでに確認コードが届いている") {awaitingEmail=true;notice=nil}
                    .font(.footnote).frame(maxWidth:.infinity)
            } else if mode=="login" {
                Button("パスワードを忘れた？") {mode="recovery"}
                    .font(.footnote).frame(maxWidth:.infinity)
            } else {
                Button("ログインに戻る") {mode="login"}
                    .font(.footnote).frame(maxWidth:.infinity)
            }
        }
        .padding(16)
        .background(.white,in:RoundedRectangle(cornerRadius:24))
    }

    private func inputLabel(_ title:String)->some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
    }

    private func verificationCard(recovery:Bool)->some View {
        VStack(alignment:.leading,spacing:16) {
            Label(address,systemImage:"envelope.fill")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            inputLabel("確認コード")
            TextField("メールに届いた数字",text:$code)
                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                .textFieldStyle(AuthInputStyle())
                .accessibilityIdentifier("account-verification-code")
            Button(recovery ? "コードを確認する" : "登録を完了する") {verifyCode(recovery:recovery)}
                .frame(maxWidth:.infinity).buttonStyle(CoralButtonStyle())
                .disabled(client.busy || !SignupRequirements.validEmail(address) || code.count<6)
                .opacity(client.busy || code.count<6 ? 0.45 : 1)
                .accessibilityIdentifier("account-verify")
            Text("届かない？ 迷惑メールを確認してみてね。")
                .font(.caption).foregroundStyle(Theme.secondaryText)
            Button("メールを再送する") {resend(recovery:recovery)}
                .font(.footnote.weight(.semibold)).disabled(client.busy)
            Button("メールアドレスを変える") {awaitingEmail=false;code="";notice=nil}
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .padding(20)
        .background(.white,in:RoundedRectangle(cornerRadius:24))
    }

    private var newPasswordCard:some View {
        VStack(alignment:.leading,spacing:16) {
            inputLabel("新しいパスワード")
            SecureField("12文字以上",text:$password)
                .textContentType(.newPassword).textFieldStyle(AuthInputStyle())
            Button("パスワードを変更") {
                let supplied=password
                Task {await client.perform {
                    try await client.changePassword(supplied)
                    password="";passwordChanged=true;notice=nil
                }}
            }
            .frame(maxWidth:.infinity).buttonStyle(CoralButtonStyle())
            .disabled(client.busy || password.count<12)
        }
        .padding(20)
        .background(.white,in:RoundedRectangle(cornerRadius:24))
    }

    private var completedCard:some View {
        VStack(spacing:18) {
            Image(systemName:"checkmark.seal.fill")
                .font(.system(size:55)).foregroundStyle(Theme.accent)
            Text("犬猫の登録はいつでもできます。")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            Button("アプリに戻る") {dismiss()}
                .frame(maxWidth:.infinity).buttonStyle(CoralButtonStyle())
        }
        .frame(maxWidth:.infinity)
        .padding(28)
        .background(.white,in:RoundedRectangle(cornerRadius:24))
    }

    private var resetCompletedCard:some View {
        VStack(spacing:18) {
            Image(systemName:"checkmark.seal.fill")
                .font(.system(size:55)).foregroundStyle(Theme.accent)
            Text("パスワードを変更しました。")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            Button("ログインへ") {mode="login"}
                .frame(maxWidth:.infinity).buttonStyle(CoralButtonStyle())
        }
        .frame(maxWidth:.infinity)
        .padding(28)
        .background(.white,in:RoundedRectangle(cornerRadius:24))
    }

    private func submit() {
        let supplied=password,action=mode,address=address,accepted=adult && confirmed
        notice=nil
        Task {await client.perform {
            if action=="login" {
                try await client.signIn(email:address,password:supplied)
                password=""
            } else if action=="signup" {
                let active=try await client.signUp(email:address,password:supplied,confirmed:accepted)
                password="";passwordConfirmation="";awaitingEmail = !active
            } else {
                try await client.sendRecovery(email:address)
                awaitingEmail=true
                notice="アカウントがある場合はメールが届きます。"
            }
        }}
    }

    private func verifyCode(recovery:Bool) {
        let address=address,supplied=code
        Task {await client.perform {
            try await client.verifyEmail(email:address,code:supplied,recovery:recovery)
            code="";notice=nil
        }}
    }

    private func resend(recovery:Bool) {
        let address=address
        Task {await client.perform {
            if recovery {try await client.sendRecovery(email:address)}
            else {try await client.resendSignup(email:address)}
            notice="メールを再送しました。"
        }}
    }
}

private struct AuthInputStyle:TextFieldStyle {
    func _body(configuration:TextField<Self._Label>)->some View {
        configuration
            .padding(.horizontal,14)
            .frame(minHeight:50)
            .background(Theme.background,in:RoundedRectangle(cornerRadius:14))
    }
}
