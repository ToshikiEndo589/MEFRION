import XCTest

@MainActor
final class PrototypeUITests: XCTestCase {
    func testMyPageBottomActionsStayAboveFloatingTabs() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-album-fixture","--ui-profile-fixture"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        let tab=app.buttons["root-tab-マイページ"]
        tab.tap()
        XCTAssertTrue(app.buttons["open-account-profile"].waitForExistence(timeout:10))
        let retirement=app.buttons["open-account-retirement"]
        // Reach the actual resting bottom, rather than tapping during overscroll.
        for _ in 0..<4 {app.scrollViews.firstMatch.swipeUp()}
        XCTAssertTrue(retirement.isHittable)
        XCTAssertLessThan(retirement.frame.maxY,tab.frame.minY-6)
        capture(app,"My-page-bottom-clear-of-tabs")
        retirement.tap()
        XCTAssertTrue(app.navigationBars["退会・データ削除"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["account-retirement-submit"].isEnabled)
        app.navigationBars.buttons.firstMatch.tap()
        let management=app.buttons["設定・管理"]
        XCTAssertTrue(management.isHittable);management.tap()
        for _ in 0..<2 {app.scrollViews.firstMatch.swipeUp()}
        XCTAssertLessThan(retirement.frame.maxY,tab.frame.minY-6)
        retirement.tap()
        XCTAssertTrue(app.navigationBars["退会・データ削除"].waitForExistence(timeout:5))
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<6 {app.scrollViews.firstMatch.swipeDown()}
        app.buttons["設定"].tap()
        let settingsRetirement=app.buttons["アカウントを削除する"]
        for _ in 0..<3 {app.swipeUp()}
        XCTAssertTrue(settingsRetirement.isHittable)
        XCTAssertLessThan(settingsRetirement.frame.maxY,tab.frame.minY-6)
        settingsRetirement.tap()
        XCTAssertTrue(app.navigationBars["退会・データ削除"].waitForExistence(timeout:5))
        // Never confirm or submit account deletion in this navigation test.
    }
    func testSimpleAccountAndPetProfilesSaveAndReopen() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-album-fixture","--ui-profile-fixture"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        app.buttons["root-tab-マイページ"].tap()
        let account=app.buttons["open-account-profile"];XCTAssertTrue(account.waitForExistence(timeout:10));account.tap()
        XCTAssertTrue(app.buttons["profile-icon-picker"].waitForExistence(timeout:10))
        let remove=app.buttons["profile-icon-remove"];XCTAssertTrue(remove.waitForExistence(timeout:10));remove.tap()
        let accountSave=app.buttons["account-profile-save"];reveal(accountSave,in:app);accountSave.tap()
        XCTAssertTrue(app.staticTexts["account-profile-saved"].waitForExistence(timeout:10))
        capture(app,"Simple-account-profile")
        app.navigationBars.buttons.firstMatch.tap();account.tap()
        XCTAssertFalse(app.buttons["profile-icon-remove"].exists,"Removing the account icon must survive reopening")
        app.navigationBars.buttons.firstMatch.tap()
        let pet=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","cloud-pet-")).firstMatch
        reveal(pet,in:app);pet.tap()
        XCTAssertTrue(app.textFields["cloud-profile-name"].waitForExistence(timeout:10))
        XCTAssertFalse(app.textFields["誕生日（例：2021-04-05）"].exists,"Optional details start collapsed")
        let chooseAlbum=app.buttons["アルバムの写真から選ぶ"];reveal(chooseAlbum,in:app);chooseAlbum.tap()
        app.buttons["アイコン写真を選ぶ"].tap()
        let image=app.buttons["この写真を選ぶ"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout:10));expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:image);waitForExpectations(timeout:10);image.tap()
        let save=app.buttons["cloud-profile-save"];reveal(save,in:app);save.tap()
        XCTAssertTrue(app.staticTexts["cloud-profile-saved"].waitForExistence(timeout:10))
        capture(app,"Simple-pet-profile")
        app.navigationBars.buttons.firstMatch.tap();reveal(pet,in:app);pet.tap()
        XCTAssertTrue(app.buttons["profile-icon-remove"].waitForExistence(timeout:10),"Selected pet photo must survive reopening")
    }
    func testFamilyInviteLimitRecoveryAndReopenKeepsCreatedLink() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-album-fixture","--ui-family-invite-fixture"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        app.buttons["root-tab-マイページ"].tap()
        let settings=app.buttons["open-album-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout:10));reveal(settings,in:app);settings.tap()
        XCTAssertFalse(app.buttons["プロフィール"].exists)
        app.buttons["家族を招待"].tap()
        let create=app.buttons["招待リンクを作る"]
        XCTAssertTrue(create.waitForExistence(timeout:10));create.tap()
        XCTAssertTrue(app.buttons["古いリンクを取り消して作り直す"].waitForExistence(timeout:10))
        app.buttons["今はやめる"].tap()
        XCTAssertTrue(create.exists,"Cancel must not create or replace any invite")
        create.tap();app.buttons["古いリンクを取り消して作り直す"].tap()
        XCTAssertTrue(app.buttons["招待リンクを送る"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["このリンクから参加できるのは1人です"].exists)
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.buttons["家族を招待"].tap()
        XCTAssertTrue(app.buttons["招待リンクを送る"].waitForExistence(timeout:10))
        XCTAssertFalse(create.exists,"Reopening must show the existing invite, not ask to create another")
        capture(app,"Family-invite-recovered-and-restored")
    }
    func testPostDoubleTapOffersLoginWithoutStealingCarouselSwipe() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-feed-fixture"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        let photo=app.images["cloud-public-image"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout:10))
        photo.doubleTap()
        XCTAssertTrue(app.buttons["auth-resume-cancel"].waitForExistence(timeout:10))
    }
    func testReferenceSearchAutomaticallyAppearsIn24HourHistory() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-stock-twins"];app.launch()
        app.buttons["root-tab-そっくり"].tap()
        let sample=app.buttons["reference-twins-sample"]
        XCTAssertTrue(sample.waitForExistence(timeout:15))
        reveal(sample,in:app);sample.tap()
        app.buttons["reference-twins-search"].tap()
        XCTAssertTrue(app.staticTexts["そっくりな子、見つけた！"].waitForExistence(timeout:30))
        app.buttons["reference-twins-more"].tap()
        app.buttons["そっくりの履歴"].tap()
        XCTAssertTrue(app.buttons["この検索履歴を削除"].firstMatch.waitForExistence(timeout:10))
        XCTAssertFalse(app.staticTexts["まだ履歴はないよ ♡"].exists)
        XCTAssertTrue(app.images.matching(NSPredicate(format:"identifier BEGINSWITH %@","history-query-photo-")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["検索した写真"].exists)
        XCTAssertTrue(app.staticTexts["そっくりな子たち"].exists)
        capture(app,"Reference-auto-history-24-hours")
    }
    func testHomeTabReselectScrollsToTopAndRefreshesFeed() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-feed-fixture"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        let posts=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","cloud-open-post-fixture-post-"))
        let first=posts.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout:10))
        let originalID=first.identifier
        // Start within the feed; a root-app swipe can begin on the fixed tab bar.
        let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.65))
        let end=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25))
        for _ in 0..<4 {start.press(forDuration:0.05,thenDragTo:end)}
        capture(app,"Home-feed-after-four-vertical-drags")
        XCTAssertFalse(app.buttons[originalID].isHittable,"The original post should have scrolled away")
        let visibleImages=app.images.matching(identifier:"cloud-public-image").allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertFalse(visibleImages.isEmpty,"A later post should decode from the in-memory compressed cache")
        app.buttons["root-tab-ホーム"].tap()
        let changed=NSPredicate(format:"identifier != %@",originalID)
        expectation(for:changed,evaluatedWith:posts.firstMatch)
        waitForExpectations(timeout:10)
        XCTAssertTrue(posts.firstMatch.isHittable,"Reselecting Home should return to a new top post")
    }
    func testRecommendedPullToRefreshKeepsFixtureFeedVisible() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-feed-fixture"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        let posts=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","cloud-open-post-fixture-post-"))
        XCTAssertTrue(posts.firstMatch.waitForExistence(timeout:10))
        let gesture=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.20))
        gesture.press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.72)))
        XCTAssertTrue(posts.firstMatch.waitForExistence(timeout:10))
        XCTAssertGreaterThan(posts.count,0)
        XCTAssertFalse(app.otherElements["public-feed-skeleton"].exists)
    }
    func testPublicPostMediaSwipesWithoutMovingToNextPost() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-feed-fixture"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        let firstPost=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","cloud-open-post-fixture-post-")).firstMatch
        XCTAssertTrue(firstPost.waitForExistence(timeout:10))
        let originalID=firstPost.identifier
        let carousel=app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@","cloud-media-carousel-fixture-post-")).firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["1/2"].firstMatch.exists)
        carousel.swipeLeft()
        XCTAssertTrue(app.staticTexts["2/2"].firstMatch.waitForExistence(timeout:5))
        XCTAssertEqual(firstPost.identifier,originalID)
        carousel.swipeRight()
        XCTAssertTrue(app.staticTexts["1/2"].firstMatch.waitForExistence(timeout:5))
    }
    func testAlbumPullToRefreshKeepsExistingPhotosVisible() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-album-fixture"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        app.buttons["root-tab-アルバム"].tap()
        let photo=app.buttons["cloud-album-gallery-photo-fixture-album-photo"]
        XCTAssertTrue(photo.waitForExistence(timeout:10))
        let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25))
        start.press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.75)))
        XCTAssertTrue(photo.exists,"Refresh should retain the gallery while the request is in flight")
        XCTAssertTrue(photo.waitForExistence(timeout:5))
        XCTAssertFalse(app.otherElements["album-gallery-skeleton"].exists)
    }
    func testAlbumGestureAtlasWithoutThenNow() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-album-fixture"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        app.buttons["root-tab-アルバム"].tap()
        XCTAssertFalse(app.buttons["album-then-now"].exists)
        app.buttons["album-gesture-atlas"].tap()
        let sleep=app.buttons["gesture-category-sleep"]
        XCTAssertTrue(sleep.waitForExistence(timeout:10));sleep.tap()
        let photo=app.buttons["図鑑に入れる、おひるね"]
        XCTAssertTrue(photo.waitForExistence(timeout:10));photo.tap()
        app.buttons["できた"].tap()
        XCTAssertTrue(app.staticTexts["1 / 6 しぐさ集まったよ"].waitForExistence(timeout:10))
        capture(app,"Album-gesture-atlas")
        sleep.tap()
        XCTAssertTrue(app.buttons["図鑑から外す、おひるね"].waitForExistence(timeout:10))
    }
    func testAccountDeletionIsReachableFromMyPage() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-album-fixture"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        app.buttons["root-tab-マイページ"].tap()
        let route=app.buttons["open-account-retirement"]
        XCTAssertTrue(route.waitForExistence(timeout:10));reveal(route,in:app);route.tap()
        XCTAssertTrue(app.navigationBars["退会・データ削除"].waitForExistence(timeout:10))
        XCTAssertTrue(app.switches["retirement-confirm"].exists)
        XCTAssertFalse(app.buttons["account-retirement-submit"].isEnabled)
    }
    func testTwinsHistoryIsReachableFromMyPage() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-album-fixture"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        app.buttons["root-tab-マイページ"].tap()
        let route=app.buttons["open-twins-history"]
        XCTAssertTrue(route.waitForExistence(timeout:10));reveal(route,in:app);route.tap()
        XCTAssertTrue(app.navigationBars["検索履歴"].waitForExistence(timeout:10))
    }
    private func dismissPasswordSuggestion(in app:XCUIApplication) {
        // iOS presents its password generator in place of the keyboard. Typing
        // through that remote view does not exercise normal password entry.
        if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout:2) {
            app.buttons["xmark"].tap()
        }
    }
    private func signupFixture(password:String)->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-signup-fixture"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        app.buttons["root-tab-マイページ"].tap()
        let account=app.buttons["登録・ログイン"];XCTAssertTrue(account.waitForExistence(timeout:10));account.tap()
        let registration=app.buttons["メールで新規登録"];reveal(registration,in:app);registration.tap()
        let email=app.textFields["account-email"];XCTAssertTrue(email.waitForExistence(timeout:10));email.tap();email.typeText("pet.owner@example.com")
        let field=app.secureTextFields["account-password"];reveal(field,in:app);field.tap();dismissPasswordSuggestion(in:app);app.typeText(password)
        let countAfterPassword=app.staticTexts["signup-fixture-counts"].label
        XCTContext.runActivity(named:"After primary input: "+countAfterPassword+" "+field.label) {_ in}
        let confirmation=app.secureTextFields["account-password-confirmation"];reveal(confirmation,in:app);confirmation.tap();dismissPasswordSuggestion(in:app);app.typeText(password)
        XCTContext.runActivity(named:"After confirmation input: "+app.staticTexts["signup-fixture-counts"].label+" "+field.label+" "+confirmation.label) {_ in}
        if app.buttons["完了"].exists {app.buttons["完了"].firstMatch.tap()}
        let adult=app.switches["account-adult"],privacy=app.switches["account-privacy"]
        reveal(adult,in:app);adult.tap();reveal(privacy,in:app);privacy.tap()
        return app
    }
    func testSignupSendButtonExplainsShortPasswordAndPrivacyIsSimplified() throws {
        let app=signupFixture(password:"Paw12345")
        let submit=app.buttons["account-submit"];reveal(submit,in:app)
        XCTAssertTrue(submit.isEnabled);submit.tap()
        XCTAssertTrue(app.staticTexts["パスワードは12文字以上にしてね"].waitForExistence(timeout:5))
        capture(app,"Signup-actionable-password-help")
        app.buttons["データの取り扱いを見る"].tap()
        XCTAssertTrue(app.navigationBars["プライバシーと同意"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["利用条件"].exists)
        XCTAssertFalse(app.staticTexts["写真の公開"].exists)
        XCTAssertFalse(app.staticTexts["Twins"].exists)
        XCTAssertTrue(app.buttons["プライバシーポリシー"].exists || app.links["プライバシーポリシー"].exists)
        capture(app,"Privacy-without-long-feature-explanations")
    }
    func testValidSignupReachesEmailCodeWithFloatingTabs() throws {
        let app=signupFixture(password:"Paw12345more")
        let submit=app.buttons["account-submit"];reveal(submit,in:app);XCTAssertTrue(submit.isEnabled);submit.tap()
        XCTAssertTrue(app.textFields["account-verification-code"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["root-tab-マイページ"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists,"Only the floating tab bar should be visible")
        capture(app,"Signup-code-step-floating-tabs")
    }
    func testSignupExplainsRequirementsAndConfirmsPassword() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"];app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        app.buttons["root-tab-マイページ"].tap()
        let account=app.buttons["登録・ログイン"];XCTAssertTrue(account.waitForExistence(timeout:10));account.tap()
        let registration=app.buttons["メールで新規登録"];reveal(registration,in:app);registration.tap()
        let confirmation=app.descendants(matching:.any).matching(identifier:"account-password-confirmation").firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout:10))
        XCTAssertFalse(app.textFields["account-pet-name"].exists)
        XCTAssertFalse(app.textFields["account-pet-breed"].exists)
        XCTAssertFalse(app.textFields["account-display-name"].exists)
        XCTAssertTrue(app.staticTexts["犬猫を飼っていなくても、見るだけでも大歓迎。"].exists)
        capture(app,"Email-signup-without-Pet")
        let password=app.secureTextFields["account-password"]
        reveal(password,in:app);password.tap();password.typeText("a-long-password-123")
        reveal(confirmation,in:app);confirmation.tap()
        XCTAssertTrue(confirmation.exists)
    }
    func testPostSelectionGoesDirectlyToCaption() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-album-fixture"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1"
        app.launch();app.buttons["root-tab-投稿"].tap()
        let choose=app.buttons["quick-post-fixture-photo"]
        XCTAssertTrue(choose.waitForExistence(timeout:20));choose.tap()
        let next=app.buttons["quick-post-next"]
        XCTAssertTrue(next.waitForExistence(timeout:10));next.tap()
        XCTAssertTrue(app.textViews["quick-post-caption"].waitForExistence(timeout:10))
        XCTAssertFalse(app.textFields["post-sticker-text"].exists)
        XCTAssertFalse(app.buttons["post-add-music"].exists)
        XCTAssertTrue(app.buttons["quick-post-submit"].exists)
        app.buttons["quick-post-back-media"].tap()
        XCTAssertTrue(app.buttons["quick-post-thumbnail-0"].waitForExistence(timeout:10))
        // The album destination follows the same direct flow without publishing test content.
        let destination=app.segmentedControls["cloud-composer-destination"]
        destination.buttons["アルバムに残す"].tap()
        next.tap()
        XCTAssertTrue(app.textViews["quick-post-caption"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["quick-post-submit"].exists)
        capture(app,"Post-caption-without-decoration")
    }
    func testQuickPostLetsTheUserRemoveMediaBeforePosting() throws {
        let fixtureURL=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("cloud-fixture.json")
        guard let data=try? Data(contentsOf:fixtureURL) else {throw XCTSkip("Synthetic cloud fixture absent")}
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:String])
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1"
        app.launchEnvironment["MEFRION_CLOUD_PUBLIC_KEY"]=fixture["anon_key"]
        app.launchEnvironment["MEFRION_TEST_CLOUD_EMAIL"]=fixture["email"]
        app.launchEnvironment["MEFRION_TEST_CLOUD_PASSWORD"]=fixture["password"]
        app.launch();app.buttons["root-tab-投稿"].tap()
        let choose=app.buttons["quick-post-pick-photos"]
        XCTAssertTrue(choose.waitForExistence(timeout:30))
        XCTAssertTrue(app.buttons["quick-post-camera"].exists)
        XCTAssertFalse(app.buttons["cloud-import-confirm"].exists)
        app.buttons["quick-post-fixture-photo"].tap()
        XCTAssertTrue(app.buttons["quick-post-thumbnail-0"].waitForExistence(timeout:10))
        app.buttons["quick-post-remove-0"].tap()
        XCTAssertFalse(app.buttons["quick-post-thumbnail-0"].exists)
        app.buttons["quick-post-fixture-photo"].tap()
        let next=app.buttons["quick-post-next"]
        XCTAssertTrue(next.waitForExistence(timeout:10))
        next.tap()
        XCTAssertTrue(app.textViews["quick-post-caption"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["quick-post-photo-consent"].exists)
        let submit=app.buttons["quick-post-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout:10))
        XCTAssertTrue(submit.isEnabled)
        capture(app,"Quick-post-caption-before-submit")
        submit.tap()
        XCTAssertTrue(app.buttons["自分の投稿を見る"].waitForExistence(timeout:60),"The server must acknowledge the post without a success alert")
        XCTAssertFalse(app.alerts["投稿を受け付けました！"].exists)
        app.buttons["自分の投稿を見る"].tap()
        let ownPost=app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@","my-post-")).firstMatch
        XCTAssertTrue(ownPost.waitForExistence(timeout:20),"An accepted post must appear in the owner's list")
        capture(app,"My-posts-two-column-grid")
        let postID=String(ownPost.identifier.dropFirst("my-post-".count))
        app.buttons["my-post-delete-"+postID].tap()
        let confirmDelete=app.buttons["投稿を削除"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout:10))
        confirmDelete.tap()
        let removed=NSPredicate(format:"exists == false")
        expectation(for:removed,evaluatedWith:ownPost)
        waitForExpectations(timeout:20)
        app.navigationBars["自分の投稿"].buttons.firstMatch.tap()
        app.buttons["root-tab-アルバム"].tap()
        XCTAssertFalse(app.buttons["cloud-album-add-photos"].exists,"Album tab is viewing only; upload lives in Post")
        capture(app,"Album-view-only-after-public-post")
        app.buttons["root-tab-投稿"].tap()
        let cleanup=app.buttons["quick-post-fixture-cleanup"]
        XCTAssertTrue(cleanup.waitForExistence(timeout:60),"The direct composer should reach server acceptance")
        cleanup.tap()
        XCTAssertTrue(app.buttons["quick-post-fixture-photo"].waitForExistence(timeout:45))
        XCTAssertFalse(cleanup.exists)
        let destination=app.segmentedControls["cloud-composer-destination"]
        destination.buttons["アルバムに残す"].tap()
        XCTAssertTrue(app.buttons["quick-post-pick-photos"].waitForExistence(timeout:20),"Album upload is available from Post")
        XCTAssertTrue(destination.waitForExistence(timeout:10))
        destination.buttons["公開投稿"].tap()
        app.buttons["root-tab-マイページ"].tap()
        XCTAssertTrue(app.buttons["open-my-posts"].waitForExistence(timeout:20))
        XCTAssertTrue(app.staticTexts["自分の投稿"].exists)
    }
    func testLiveCloudHomeScrollKeepsItsPosition() throws {
        guard ProcessInfo.processInfo.environment["MEFRION_TEST_LIVE_FEED_APPROVED"]=="1" else {
            throw XCTSkip("Run only while approved temporary public test posts are available")
        }
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1"
        app.launch()
        let posts=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","cloud-open-post-"))
        XCTAssertTrue(posts.firstMatch.waitForExistence(timeout:25))
        let startingPost=posts.firstMatch.identifier
        for _ in 0..<4 {app.swipeUp()}
        let visible=posts.allElementsBoundByIndex.filter(\.isHittable).map(\.identifier)
        XCTAssertFalse(visible.isEmpty,"Scrolling should leave a visible feed post")
        XCTAssertFalse(visible.contains(startingPost),"Scrolling down returned to the first post")
        XCUIDevice.shared.press(.home)
        app.activate()
        let afterReturn=posts.allElementsBoundByIndex.filter(\.isHittable).map(\.identifier)
        XCTAssertFalse(afterReturn.isEmpty,"Returning to the app should keep the feed visible")
        XCTAssertFalse(afterReturn.contains(startingPost),"Returning to the app reset the feed to the top")
    }
    func testLiveHomeDeepScrollDoesNotJumpBackToTop() throws {
        guard ProcessInfo.processInfo.environment["MEFRION_TEST_LIVE_FEED_APPROVED"]=="1" else {
            throw XCTSkip("Run only while approved temporary public test posts are available")
        }
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        let posts=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","cloud-open-post-"))
        XCTAssertTrue(posts.firstMatch.waitForExistence(timeout:25))
        let firstID=posts.firstMatch.identifier
        var seenRanks:[String:Int]=[:]
        for step in 0..<58 {
            app.swipeUp()
            let visible=posts.allElementsBoundByIndex.filter(\.isHittable).sorted{$0.frame.minY<$1.frame.minY}
            for post in visible where seenRanks[post.identifier]==nil {seenRanks[post.identifier]=seenRanks.count}
            if let front=visible.first,let rank=seenRanks[front.identifier] {
                XCTAssertGreaterThanOrEqual(rank,max(0,seenRanks.count-8),"Feed jumped backward at swipe \(step)")
            }
            if step>=3 {
                XCTAssertFalse(posts.allElementsBoundByIndex.contains(where:{$0.identifier==firstID && $0.isHittable}),
                               "Deep scroll returned to the first post at swipe \(step)")
            }
        }
        print("Deep scroll observed \(seenRanks.count) distinct post headers")
        XCTAssertGreaterThanOrEqual(seenRanks.count,25,"Deep scroll should visit a substantial part of the feed")
        XCTAssertTrue(posts.allElementsBoundByIndex.contains(where:\.isHittable))
    }
    func testLiveRecommendedReloadShowsDifferentTopPost() throws {
        guard ProcessInfo.processInfo.environment["MEFRION_TEST_LIVE_FEED_APPROVED"]=="1" else {
            throw XCTSkip("Run only while approved temporary public test posts are available")
        }
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        let posts=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","cloud-open-post-"))
        XCTAssertTrue(posts.firstMatch.waitForExistence(timeout:25))
        let firstID=posts.firstMatch.identifier
        app.buttons["root-tab-ホーム"].tap()
        expectation(for:NSPredicate(format:"identifier != %@",firstID),evaluatedWith:posts.firstMatch)
        waitForExpectations(timeout:15)
        XCTAssertTrue(posts.firstMatch.isHittable)
    }
    func testLiveManagedPostShowsPetNameAndOnlyKnownBreed() throws {
        guard ProcessInfo.processInfo.environment["MEFRION_TEST_LIVE_FEED_APPROVED"]=="1" else {
            throw XCTSkip("Run only while approved temporary public test posts are available")
        }
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        let accounts=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","cloud-open-post-"))
        XCTAssertTrue(accounts.firstMatch.waitForExistence(timeout:25))
        let names=accounts.allElementsBoundByIndex.map(\.label)
        XCTAssertFalse(names.isEmpty)
        XCTAssertEqual(names.count,Set(names).count,"One visible managed post should represent one Pet")
        XCTAssertFalse(names.contains(where:{$0.contains("犬の写真") || $0.contains("猫の写真")}))
        XCTAssertFalse(names.contains(where:{$0.contains("わんこ日和") || $0.contains("にゃんこ日和")}))
        let labels=app.staticTexts.matching(NSPredicate(format:"identifier BEGINSWITH %@","cloud-post-breed-"))
        XCTAssertFalse(labels.allElementsBoundByIndex.contains(where:{$0.label.contains("推定") || $0.label.contains("未確認") || $0.label=="犬" || $0.label=="猫"}))
    }
    func testLiveRecommendedPullToRefreshKeepsPostsVisible() throws {
        guard ProcessInfo.processInfo.environment["MEFRION_TEST_LIVE_FEED_APPROVED"]=="1" else {
            throw XCTSkip("Run only while approved temporary public test posts are available")
        }
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        let posts=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","cloud-open-post-"))
        XCTAssertTrue(posts.firstMatch.waitForExistence(timeout:25))
        let firstID=posts.firstMatch.identifier
        let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.20))
        let end=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.72))
        start.press(forDuration:0.1,thenDragTo:end)
        expectation(for:NSPredicate(format:"identifier != %@",firstID),evaluatedWith:posts.firstMatch)
        waitForExpectations(timeout:20)
        XCTAssertGreaterThan(posts.count,0,"Pull refresh must not remove the feed")
        XCTAssertTrue(posts.firstMatch.isHittable,"Pull refresh should leave a visible first post")
        XCTAssertTrue(app.images["cloud-public-image"].firstMatch.waitForExistence(timeout:15),"Pull refresh should restore the first image")
    }
    func testLiveCloudHomeUsesFullWidthMediaAndActionRow() throws {
        guard ProcessInfo.processInfo.environment["MEFRION_TEST_LIVE_FEED_APPROVED"]=="1" else {
            throw XCTSkip("Run only while approved temporary public test posts are available")
        }
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        let started=CFAbsoluteTimeGetCurrent()
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        let photo=app.images["cloud-public-image"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout:15))
        XCTContext.runActivity(named:"First visible feed image after app.launch: \(String(format:"%.2f",CFAbsoluteTimeGetCurrent()-started))s") {_ in}
        XCTAssertLessThanOrEqual(photo.frame.minX,2)
        XCTAssertGreaterThanOrEqual(photo.frame.maxX,app.frame.width-2)
        let like=app.buttons["cloud-guest-like"].firstMatch
        let comment=app.buttons["cloud-comments-post"].firstMatch
        XCTAssertTrue(like.exists);XCTAssertTrue(comment.exists)
        XCTAssertEqual(like.frame.midY,comment.frame.midY,accuracy:3)
        reveal(like,in:app);like.tap()
        XCTAssertTrue(app.buttons["auth-resume-cancel"].waitForExistence(timeout:10))
    }
    func testReferenceTwinsPhotoSearchAndPrivateDiscard() throws {try runReferenceTwinsPhotoSearch(server:false)}
    func testReferenceTwinsServerSearchAndPrivateDiscard() throws {try runReferenceTwinsPhotoSearch(server:true)}
    func testReferenceTwinsCameraCapture() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-stock-twins"];app.launch()
        app.buttons["root-tab-そっくり"].tap()
        app.buttons["reference-twins-camera"].tap()
        let shutter=app.buttons["PhotoCapture"]
        #if targetEnvironment(simulator)
        guard shutter.waitForExistence(timeout:8) else {throw XCTSkip("このシミュレータには撮影可能なカメラがありません")}
        #else
        XCTAssertTrue(shutter.waitForExistence(timeout:8),"実機でカメラ画面が開きません")
        #endif
        shutter.tap()
        let search=app.buttons["reference-twins-search"]
        if !search.isEnabled {
            let use=app.buttons["写真を使用"].exists ? app.buttons["写真を使用"] : app.buttons["Use Photo"]
            XCTAssertTrue(use.waitForExistence(timeout:8),"撮影した写真がアプリに戻りません")
            use.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout:10))
        XCTAssertTrue(search.isEnabled)
    }
    private func runReferenceTwinsPhotoSearch(server:Bool) throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-stock-twins"]
        if server {app.launchArguments.append("--server-reference-probe")}
        app.launch()
        app.buttons["root-tab-そっくり"].tap()
        XCTAssertTrue(app.buttons["reference-twins-picker"].waitForExistence(timeout:20))
        let camera=app.buttons["reference-twins-camera"]
        XCTAssertTrue(camera.exists)
        // Camera capture has its own test and needs device-specific permissions.
        // Keep this search/share/privacy scenario independent of camera hardware.
        let sample=app.buttons["reference-twins-sample"]
        for _ in 0..<6 where !sample.isHittable {app.swipeUp()}
        XCTAssertTrue(sample.waitForExistence(timeout:10));sample.tap()
        XCTAssertFalse(app.switches["reference-twins-consent"].exists)
        let search=app.buttons["reference-twins-search"]
        XCTAssertTrue(search.isEnabled)
        for _ in 0..<6 where !sample.isHittable {app.swipeUp()};sample.tap()
        XCTAssertTrue(search.isEnabled)
        search.tap()
        XCTAssertTrue(app.staticTexts["そっくりな子、見つけた！"].waitForExistence(timeout:30))
        XCTAssertFalse(app.staticTexts["参考写真"].exists)
        XCTAssertFalse(app.buttons["似てる"].exists)
        XCTAssertFalse(app.buttons["ちょっと違う"].exists)
        capture(app,server ? "Reference-twins-server-results" : "Reference-twins-real-photo-results")
        let share=app.buttons["reference-twins-share"]
        reveal(share,in:app);XCTAssertTrue(share.isHittable)
        share.tap()
        XCTAssertTrue(app.navigationBars["そっくりカード"].waitForExistence(timeout:10))
        capture(app,server ? "Reference-twins-server-share" : "Reference-twins-share")
        app.buttons["X ポスト"].tap()
        XCTAssertTrue(app.buttons["reference-twins-x-share"].waitForExistence(timeout:10))
        capture(app,server ? "Reference-twins-server-x-card" : "Reference-twins-x-card")
        app.buttons["閉じる"].tap()
        let more=app.buttons["reference-twins-more"]
        XCTAssertTrue(more.isHittable)
        XCTAssertLessThanOrEqual(more.frame.maxX,app.frame.maxX)
        more.tap()
        let discard=app.buttons["reference-twins-discard"]
        XCTAssertTrue(discard.waitForExistence(timeout:5));discard.tap()
        XCTAssertFalse(app.otherElements["reference-twins-main"].exists)
        XCTAssertFalse(app.staticTexts["そっくりな子、見つけた！"].exists)
        XCTAssertFalse(app.buttons["reference-twins-search"].isEnabled)
        capture(app,server ? "Reference-twins-server-input-erased" : "Reference-twins-private-input-erased")
    }
    func testCloudHorizontalTabsAndPublicComposerDefault() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        XCTAssertTrue(app.buttons["home-recommended"].waitForExistence(timeout:10))
        func swipe(_ left:Bool) {
            app.coordinate(withNormalizedOffset:CGVector(dx:left ? 0.8 : 0.2,dy:0.4))
                .press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:left ? 0.2 : 0.8,dy:0.4)))
        }
        swipe(true)
        XCTAssertEqual(app.buttons["home-following"].value as? String,"選択中")
        XCTAssertTrue(app.buttons["ログインしてフォロー・投稿する"].waitForExistence(timeout:10))
        swipe(false)
        XCTAssertEqual(app.buttons["home-recommended"].value as? String,"選択中")
        XCTAssertFalse(app.buttons["ログインしてフォロー・投稿する"].exists)
        app.swipeUp()
        XCTAssertTrue(app.buttons["root-tab-ホーム"].isSelected)
        app.buttons["root-tab-投稿"].tap()
        let picker=app.segmentedControls["cloud-composer-destination"]
        XCTAssertTrue(picker.waitForExistence(timeout:10))
        XCTAssertTrue(picker.buttons["公開投稿"].isSelected)
        XCTAssertTrue(app.staticTexts["投稿するにはログイン"].exists)
        XCTAssertTrue(app.buttons["ログイン・新規登録"].exists)
        XCTAssertLessThan(picker.buttons["公開投稿"].frame.midX,picker.buttons["アルバムに残す"].frame.midX)
        swipe(true)
        XCTAssertTrue(picker.buttons["アルバムに残す"].isSelected)
        XCTAssertTrue(app.staticTexts["家族内のみ・非公開"].waitForExistence(timeout:10))
        swipe(false)
        XCTAssertTrue(picker.buttons["公開投稿"].isSelected)
        picker.buttons["アルバムに残す"].tap()
        XCTAssertTrue(app.staticTexts["家族内のみ・非公開"].waitForExistence(timeout:10))
        picker.buttons["公開投稿"].tap()
        XCTAssertTrue(picker.buttons["公開投稿"].isSelected)
        capture(app,"Swipe-public-composer-default")
        swipe(true);swipe(true)
        XCTAssertTrue(app.buttons["root-tab-そっくり"].isSelected)
        swipe(true)
        XCTAssertTrue(app.buttons["root-tab-マイページ"].isSelected)
        swipe(true)
        XCTAssertTrue(app.buttons["root-tab-マイページ"].isSelected)
        swipe(false)
        XCTAssertTrue(app.buttons["root-tab-そっくり"].isSelected)
        swipe(false)
        XCTAssertTrue(app.buttons["root-tab-投稿"].isSelected)
        swipe(false);swipe(false)
        XCTAssertTrue(app.buttons["root-tab-アルバム"].isSelected)
        swipe(false)
        XCTAssertTrue(app.buttons["root-tab-ホーム"].isSelected)
        swipe(false);swipe(false)
        XCTAssertTrue(app.buttons["root-tab-ホーム"].isSelected)
        XCTAssertEqual(app.buttons["home-recommended"].value as? String,"選択中")
        swipe(true);swipe(true)
        XCTAssertTrue(app.buttons["root-tab-アルバム"].isSelected)
        swipe(true)
        XCTAssertTrue(app.buttons["root-tab-投稿"].isSelected)
    }
    func testP2LaunchPerformance() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_API_BASE"]="http://127.0.0.1:8766"
        let options=XCTMeasureOptions();options.iterationCount=3
        measure(metrics:[XCTApplicationLaunchMetric()],options:options) {app.launch();app.terminate()}
    }
    func testP2HomeAccessibilityAndLargeText() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_API_BASE"]="http://127.0.0.1:8766"
        app.launch();XCTAssertTrue(app.buttons["home-search"].waitForExistence(timeout:10))
        try app.performAccessibilityAudit(for:[.hitRegion,.sufficientElementDescription,.textClipped,.contrast])
        capture(app,"P2-home-accessibility")
        app.buttons["root-tab-そっくり"].tap();XCTAssertTrue(app.buttons["アルバムから選ぶ"].waitForExistence(timeout:10))
        try app.performAccessibilityAudit(for:[.hitRegion,.sufficientElementDescription,.textClipped,.contrast])
        capture(app,"P2-twins-accessibility")
    }
    func testP2AccessibilityTextSizeNavigation() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["MEFRION_TEST_API_BASE"]="http://127.0.0.1:8766";app.launch()
        for name in ["ホーム","アルバム","投稿","そっくり","マイページ"] {let button=app.buttons["root-tab-"+name];XCTAssertTrue(button.waitForExistence(timeout:10));XCTAssertTrue(button.isHittable);XCTAssertGreaterThanOrEqual(button.frame.height,44);XCTAssertGreaterThanOrEqual(button.frame.width,44);XCTAssertLessThan(button.frame.height,100)}
        XCTAssertLessThan(app.buttons["home-recommended"].frame.height,100)
        capture(app,"P2-home-largest-text")
        app.buttons["home-search"].tap();XCTAssertTrue(app.textFields["public-search-input"].waitForExistence(timeout:10));capture(app,"P2-search-largest-text")
    }
    func testPreReleaseLegalDocumentsAccessible() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-test-onboarding"];app.launch()
        app.buttons["welcome-start"].tap()
        let information=app.buttons["利用規約・プライバシーについて"]
        if !information.isHittable {app.swipeUp()}
        XCTAssertTrue(information.waitForExistence(timeout:10));information.tap()
        app.buttons["legal-terms-draft"].tap();XCTAssertTrue(app.navigationBars["利用規約（案）"].waitForExistence(timeout:10));capture(app,"Owner-policy-terms-draft")
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.buttons["legal-privacy-draft"].tap();XCTAssertTrue(app.navigationBars["プライバシー（案）"].waitForExistence(timeout:10));capture(app,"Owner-policy-privacy-draft")
    }
    func testCloudFiveTabsAndSearchEntry() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"];app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        let brand=app.staticTexts["home-compact-brand"];XCTAssertTrue(brand.waitForExistence(timeout:10));XCTAssertEqual(brand.frame.midX,app.frame.midX,accuracy:3)
        XCTAssertFalse(app.textFields["cloud-search-query"].exists)
        XCTAssertEqual(app.buttons["home-recommended"].value as? String,"選択中")
        XCTAssertLessThan(brand.frame.minY,100)
        XCTAssertLessThanOrEqual(app.buttons["root-tab-ホーム"].frame.height,56)
        XCTAssertFalse(app.buttons["ログインしてフォロー・投稿する"].exists)
        capture(app,"Compact-cloud-home")
        app.buttons["home-following"].tap();XCTAssertTrue(app.buttons["ログインしてフォロー・投稿する"].waitForExistence(timeout:10));capture(app,"Compact-cloud-following")
        app.buttons["home-recommended"].tap();XCTAssertFalse(app.buttons["ログインしてフォロー・投稿する"].exists)
        app.buttons["home-search"].tap();XCTAssertTrue(app.textFields["cloud-search-query"].waitForExistence(timeout:10));XCTAssertTrue(app.navigationBars["検索"].exists);capture(app,"Five-tabs-cloud-search")
        app.buttons["root-tab-アルバム"].tap();XCTAssertTrue(app.buttons["ログインしてアルバムを使う"].waitForExistence(timeout:10));capture(app,"Five-tabs-cloud-album")
        app.buttons["root-tab-そっくり"].tap();XCTAssertTrue(app.buttons["写真を選ぶ"].waitForExistence(timeout:10))
        XCTAssertLessThan(app.staticTexts["twins-compact-heading"].frame.minY,110);capture(app,"Compact-cloud-twins")
        app.buttons["root-tab-マイページ"].tap();XCTAssertTrue(app.buttons["登録・ログイン"].waitForExistence(timeout:10))
    }
    func testFiveTabsCompactHomeAndSearch() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_API_BASE"]="http://127.0.0.1:8766";app.launch()
        let names=["ホーム","アルバム","投稿","そっくり","マイページ"]
        var positions:[CGFloat]=[]
        for name in names {let tab=app.buttons["root-tab-"+name];XCTAssertTrue(tab.waitForExistence(timeout:10));positions.append(tab.frame.midX)}
        XCTAssertEqual(positions,positions.sorted())
        let brand=app.staticTexts["home-compact-brand"],search=app.buttons["home-search"]
        XCTAssertTrue(brand.exists);XCTAssertLessThan(brand.frame.height,30)
        XCTAssertEqual(brand.frame.midX,app.frame.midX,accuracy:3);XCTAssertGreaterThan(search.frame.midX,brand.frame.midX)
        XCTAssertEqual(app.buttons["home-recommended"].value as? String,"選択中")
        XCTAssertLessThan(app.buttons["home-recommended"].frame.midX,app.buttons["home-following"].frame.midX)
        XCTAssertLessThan(brand.frame.minY,100)
        XCTAssertLessThanOrEqual(app.buttons["root-tab-ホーム"].frame.height,56)
        capture(app,"Compact-demo-home")
        search.tap();XCTAssertTrue(app.textFields["public-search-input"].waitForExistence(timeout:10));capture(app,"Five-tabs-search-from-header")
        app.buttons["閉じる"].tap();app.buttons["root-tab-アルバム"].tap();XCTAssertTrue(app.navigationBars["アルバム"].exists)
        app.buttons["root-tab-投稿"].tap();XCTAssertTrue(app.buttons["demo-photos"].waitForExistence(timeout:10))
        app.buttons["root-tab-そっくり"].tap();XCTAssertTrue(app.buttons["アルバムから選ぶ"].waitForExistence(timeout:10))
        XCTAssertLessThan(app.staticTexts["twins-compact-heading"].frame.minY,110);capture(app,"Compact-demo-twins")
        app.buttons["root-tab-マイページ"].tap();XCTAssertTrue(app.buttons["設定"].waitForExistence(timeout:10))
    }
    func testTwinsResultAndInputSurviveAuthentication() throws {
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("cloud-safety-fixture.json")
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:String])
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-reference-gallery"];app.launchEnvironment["MEFRION_CLOUD_PUBLIC_KEY"]=fixture["anon_key"]
        app.launch();let route=app.buttons["ui-route-08-results"];reveal(route,in:app);route.tap()
        let result=app.descendants(matching:.any)["twins-main-result"].firstMatch;reveal(result,in:app);XCTAssertTrue(result.exists)
        let authenticate=app.buttons["twins-auth-resume"];reveal(authenticate,in:app);authenticate.tap()
        let cancel=app.buttons["auth-resume-cancel"];XCTAssertTrue(cancel.waitForExistence(timeout:10));cancel.tap();reveal(result,in:app);XCTAssertTrue(result.exists)
        reveal(authenticate,in:app);authenticate.tap();let email=app.textFields["account-email"],password=app.secureTextFields["account-password"]
        XCTAssertTrue(email.waitForExistence(timeout:10));reveal(email,in:app);email.tap();email.typeText(fixture["email"]!);password.tap();password.typeText(fixture["password"]!)
        let login=app.buttons["ログイン"].firstMatch;reveal(login,in:app);login.tap()
        XCTAssertTrue(result.waitForExistence(timeout:30));reveal(result,in:app);XCTAssertTrue(result.exists);capture(app,"P0-twins-result-preserved-after-authentication")
    }
    func testCloudSessionRestoresFromIsolatedKeychainAfterRelaunch() throws {
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("cloud-safety-fixture.json")
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:String])
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"];app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launchEnvironment["MEFRION_TEST_PERSIST_SESSION"]="1"
        app.launchEnvironment["MEFRION_CLOUD_PUBLIC_KEY"]=fixture["anon_key"];app.launchEnvironment["MEFRION_TEST_CLOUD_EMAIL"]=fixture["email"];app.launchEnvironment["MEFRION_TEST_CLOUD_PASSWORD"]=fixture["password"]
        app.launch();app.buttons["root-tab-マイページ"].tap();XCTAssertTrue(app.buttons["ログアウト"].waitForExistence(timeout:30));app.terminate()
        app.launchEnvironment.removeValue(forKey:"MEFRION_TEST_CLOUD_EMAIL");app.launchEnvironment.removeValue(forKey:"MEFRION_TEST_CLOUD_PASSWORD")
        app.launch();app.buttons["root-tab-マイページ"].tap();XCTAssertTrue(app.buttons["ログアウト"].waitForExistence(timeout:30));capture(app,"P0-keychain-session-restored-after-relaunch")
        app.buttons["ログアウト"].tap();XCTAssertTrue(app.buttons["登録・ログイン"].waitForExistence(timeout:10));app.terminate()
        app.launch();app.buttons["root-tab-マイページ"].tap();XCTAssertTrue(app.buttons["登録・ログイン"].waitForExistence(timeout:10));XCTAssertFalse(app.buttons["ログアウト"].exists)
    }
    func testAccountRetirementAcceptsCurrentSession() throws {
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("retirement-fixture.json")
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:String])
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launchEnvironment["MEFRION_CLOUD_PUBLIC_KEY"]=fixture["anon_key"];app.launchEnvironment["MEFRION_TEST_CLOUD_EMAIL"]=fixture["email"];app.launchEnvironment["MEFRION_TEST_CLOUD_PASSWORD"]=fixture["password"]
        app.launch();app.buttons["root-tab-マイページ"].tap()
        let settings=app.buttons["設定"].firstMatch;XCTAssertTrue(settings.waitForExistence(timeout:30));settings.tap()
        let route=app.buttons["アカウントを削除する"];reveal(route,in:app);route.tap()
        XCTAssertFalse(app.textFields["retirement-email"].exists)
        XCTAssertFalse(app.secureTextFields["retirement-password"].exists)
        let submit=app.buttons["account-retirement-submit"]
        XCTAssertFalse(submit.isEnabled)
        let confirmation=app.switches["retirement-confirm"];reveal(confirmation,in:app);confirmation.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap();XCTAssertEqual(confirmation.value as? String,"1")
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:submit);waitForExpectations(timeout:30)
        reveal(submit,in:app);submit.tap()
        XCTAssertTrue(app.staticTexts["退会を受け付け、ログアウトしました"].waitForExistence(timeout:30));capture(app,"P0-account-retirement-native-receipt")
    }
    func testGuestAuthenticationReturnsToOriginalPost() throws {
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("cloud-safety-fixture.json")
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:String])
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launchEnvironment["MEFRION_CLOUD_PUBLIC_KEY"]=fixture["anon_key"]
        app.launch()
        let open=app.buttons["cloud-open-post-"+fixture["post_id"]!];XCTAssertTrue(open.waitForExistence(timeout:30));reveal(open,in:app);open.tap()
        let follow=app.buttons["cloud-guest-follow"];reveal(follow,in:app);XCTAssertTrue(follow.exists);expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:follow);waitForExpectations(timeout:30);if follow.label=="解除" {follow.tap();expectation(for:NSPredicate(format:"label == %@","フォロー"),evaluatedWith:follow);waitForExpectations(timeout:30)};follow.tap()
        let cancel=app.buttons["auth-resume-cancel"];XCTAssertTrue(cancel.waitForExistence(timeout:10));cancel.tap()
        XCTAssertTrue(follow.waitForExistence(timeout:10));follow.tap()
        let email=app.textFields["account-email"],password=app.secureTextFields["account-password"]
        XCTAssertTrue(email.waitForExistence(timeout:10));reveal(email,in:app);email.tap();email.typeText(fixture["email"]!)
        password.tap();password.typeText(fixture["password"]!)
        let login=app.buttons["ログイン"].firstMatch;reveal(login,in:app);login.tap()
        XCTAssertTrue(app.staticTexts["auth-resume-ready"].waitForExistence(timeout:30))
        let confirm=app.buttons["auth-resume-confirm"];reveal(confirm,in:app);XCTAssertTrue(confirm.exists);confirm.tap()
        let restored=app.buttons["cloud-follow-pet"];reveal(restored,in:app)
        expectation(for:NSPredicate(format:"label == %@","解除"),evaluatedWith:restored);waitForExpectations(timeout:30)
        capture(app,"P0-authentication-original-post-restored")
    }
    func testCloudImportRequiresConfirmationAndAllowsUndo() throws {
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("p1-card-fixture.json")
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:String])
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"];app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1"
        app.launchEnvironment["MEFRION_CLOUD_PUBLIC_KEY"]=fixture["anon_key"];app.launchEnvironment["MEFRION_TEST_CLOUD_EMAIL"]=fixture["email"];app.launchEnvironment["MEFRION_TEST_CLOUD_PASSWORD"]=fixture["password"]
        app.launch();app.buttons["root-tab-マイページ"].tap();let pet=app.buttons["cloud-pet-"+fixture["pet_id"]!];XCTAssertTrue(pet.waitForExistence(timeout:30));pet.tap()
        let open=app.buttons["cloud-import-review-fixture"];XCTAssertTrue(open.waitForExistence(timeout:30));reveal(open,in:app);open.tap()
        let confirm=app.buttons["cloud-import-confirm"];XCTAssertTrue(confirm.waitForExistence(timeout:10));XCTAssertEqual(confirm.label,"確認した2枚を追加")
        XCTAssertTrue(app.buttons.matching(identifier:"cloud-import-remove").firstMatch.waitForExistence(timeout:10))
        XCTAssertEqual(app.buttons.matching(identifier:"cloud-import-remove").count,2)
        app.buttons.matching(identifier:"cloud-import-remove").firstMatch.tap();XCTAssertEqual(confirm.label,"確認した1枚を追加")
        app.buttons.matching(identifier:"cloud-import-remove").firstMatch.tap();XCTAssertFalse(confirm.isEnabled)
        app.buttons["キャンセル"].tap();XCTAssertFalse(confirm.exists)
        open.tap();XCTAssertTrue(confirm.waitForExistence(timeout:10));XCTAssertEqual(confirm.label,"確認した2枚を追加");capture(app,"P1-import-review-before-any-upload")
        app.buttons["キャンセル"].tap();XCTAssertFalse(app.staticTexts["cloud-upload-count"].exists)
    }
    func testCloudSavedJPEGCanBeRetrievedToDevice() throws {
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("p1-card-fixture.json")
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:String])
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"];app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1"
        app.launchEnvironment["MEFRION_CLOUD_PUBLIC_KEY"]=fixture["anon_key"];app.launchEnvironment["MEFRION_TEST_CLOUD_EMAIL"]=fixture["email"];app.launchEnvironment["MEFRION_TEST_CLOUD_PASSWORD"]=fixture["password"]
        app.launch();app.buttons["root-tab-マイページ"].tap();let pet=app.buttons["cloud-pet-"+fixture["pet_id"]!];XCTAssertTrue(pet.waitForExistence(timeout:30));pet.tap()
        let photoActions=app.buttons["写真の操作"].firstMatch;XCTAssertTrue(photoActions.waitForExistence(timeout:30));reveal(photoActions,in:app);photoActions.tap()
        let save=app.buttons["cloud-save-photo-"+fixture["first"]!];XCTAssertTrue(save.waitForExistence(timeout:30));reveal(save,in:app);expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:save);waitForExpectations(timeout:30);save.tap()
        let confirm=app.buttons["この端末に保存"];XCTAssertTrue(confirm.waitForExistence(timeout:10));confirm.tap()
        let success=app.staticTexts["保存済みJPEGを端末に保存しました。端末側のコピーはアプリの削除と連動しません。"]
        XCTAssertTrue(success.waitForExistence(timeout:30));reveal(success,in:app);capture(app,"P1-saved-JPEG-retrieved-with-fresh-family-auth")
    }
    func testNormalCloudTwinsInputErasedOnTabExit() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"];app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1";app.launch()
        app.buttons["root-tab-そっくり"].tap();let demo=app.buttons["cloud-twins-demo"];XCTAssertTrue(demo.waitForExistence(timeout:10));reveal(demo,in:app);demo.tap()
        XCTAssertFalse(app.switches["cloud-twins-consent"].exists)
        XCTAssertTrue(app.buttons["cloud-twins-search"].isEnabled)
        let crop=app.buttons["写真を確認・切り抜く"];XCTAssertTrue(crop.exists)
        app.buttons["root-tab-ホーム"].tap();app.buttons["root-tab-そっくり"].tap();XCTAssertFalse(app.buttons["写真を確認・切り抜く"].exists);capture(app,"P1-normal-cloud-twins-input-erased")
    }
    func testCloudProfileAndMilestoneScreensUseNormalAccount() throws {
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("cloud-fixture.json")
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:String])
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"];app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1"
        app.launchEnvironment["MEFRION_CLOUD_PUBLIC_KEY"]=fixture["anon_key"];app.launchEnvironment["MEFRION_TEST_CLOUD_EMAIL"]=fixture["email"];app.launchEnvironment["MEFRION_TEST_CLOUD_PASSWORD"]=fixture["password"]
        app.launch();app.buttons["root-tab-マイページ"].tap()
        let pet=app.buttons["cloud-pet-"+fixture["pet_id"]!];XCTAssertTrue(pet.waitForExistence(timeout:30));pet.tap()
        let edit=app.buttons["プロフィールを編集"];reveal(edit,in:app);XCTAssertTrue(edit.waitForExistence(timeout:10));edit.tap()
        XCTAssertTrue(app.textFields["cloud-profile-name"].waitForExistence(timeout:20))
        let save=app.buttons["cloud-profile-save"];reveal(save,in:app);expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:save);waitForExpectations(timeout:30);save.tap()
        let saved=app.staticTexts["cloud-profile-saved"];reveal(saved,in:app);XCTAssertTrue(saved.waitForExistence(timeout:30));capture(app,"P1-cloud-profile-saved")
        app.navigationBars.buttons.firstMatch.tap()
        let event=app.buttons["記念日"];reveal(event,in:app);event.tap()
        XCTAssertTrue(app.textFields["cloud-event-title"].waitForExistence(timeout:20));capture(app,"P1-cloud-events-and-pet-notifications")
    }
    func testUnifiedCloudHomeAndAccountSession() throws {
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("cloud-safety-fixture.json")
        let data=try Data(contentsOf:url),fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:String])
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_USE_CLOUD"]="1"
        app.launchEnvironment["MEFRION_CLOUD_PUBLIC_KEY"]=fixture["anon_key"];app.launchEnvironment["MEFRION_TEST_CLOUD_EMAIL"]=fixture["email"];app.launchEnvironment["MEFRION_TEST_CLOUD_PASSWORD"]=fixture["password"]
        app.launch()
        let recommended=app.buttons["home-recommended"],following=app.buttons["home-following"]
        XCTAssertTrue(recommended.waitForExistence(timeout:30));XCTAssertEqual(recommended.value as? String,"選択中");XCTAssertLessThan(recommended.frame.midX,following.frame.midX)
        let open=app.buttons["cloud-open-post-"+fixture["post_id"]!]
        XCTAssertTrue(open.waitForExistence(timeout:30));reveal(open,in:app);open.tap()
        let follow=app.buttons["cloud-follow-pet"].firstMatch;reveal(follow,in:app);XCTAssertTrue(follow.exists);expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:follow);waitForExpectations(timeout:30);if follow.label=="解除" {follow.tap();expectation(for:NSPredicate(format:"label == %@","フォロー"),evaluatedWith:follow);waitForExpectations(timeout:30)};follow.tap()
        expectation(for:NSPredicate(format:"label == %@","解除"),evaluatedWith:follow);waitForExpectations(timeout:30)
        capture(app,"P0-unified-cloud-post-detail")
        app.navigationBars.buttons.firstMatch.tap()
        reveal(following,in:app);following.tap()
        XCTAssertTrue(app.images["cloud-public-image"].waitForExistence(timeout:30));capture(app,"P0-unified-following-feed")
        app.buttons["root-tab-マイページ"].tap()
        XCTAssertTrue(app.buttons["提供した写真の公開同意"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["ログアウト"].exists)
        app.buttons["root-tab-投稿"].tap()
        app.segmentedControls["cloud-composer-destination"].buttons["アルバムに残す"].tap()
        XCTAssertTrue(app.staticTexts["家族内のみ・非公開"].waitForExistence(timeout:10));capture(app,"P0-unified-private-composer")
        app.buttons["root-tab-マイページ"].tap();app.buttons["ログアウト"].tap()
        XCTAssertTrue(app.buttons["登録・ログイン"].waitForExistence(timeout:10));capture(app,"P0-unified-account-logged-out")
    }
    func testAllTenReferenceGroupsHaveRenderedScreens() throws {
        let routes=["01-intro","01-auth","01-invitation","02-home","02-detail","03-create-pet","03-edit-pet","03-public-settings","03-public-profile","04-album","04-add-photos","04-event","05-invite","05-members","05-activity","06-memories","06-card","07-post","07-confirm","07-comments","08-twins","08-crop","08-results","08-empty","08-history","09-search","09-notifications","10-owner","10-viewer","10-settings"]
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-reference-gallery","--ui-preview-sequence"]
        app.launchEnvironment["MEFRION_TEST_API_BASE"]="http://127.0.0.1:8766";app.launch()
        for route in routes {
            XCTAssertTrue(app.staticTexts["ui-preview-current"].waitForExistence(timeout:10));XCTAssertEqual(app.staticTexts["ui-preview-current"].label,route)
            XCTAssertTrue(app.staticTexts["UIプレビュー · 合成データ · クラウド送信なし"].waitForExistence(timeout:10),route)
            if route=="08-results" || route=="08-empty" {for _ in 0..<3 {app.swipeUp()}}
            capture(app,"UI-Reference-"+route)
            // XCTest may report a stale hit point while navigation preferences settle.
            // Tap through XCTest and require the actual next route on the following iteration.
            app.buttons["ui-preview-next"].tap()
        }
        XCTAssertEqual(app.staticTexts["ui-preview-current"].label,routes[0])
    }
    func testOnboardingDefaultRecommendationAndSearchNotifications() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-test-onboarding"]
        app.launchEnvironment["MEFRION_TEST_API_BASE"]="http://127.0.0.1:8766";app.launch()
        XCTAssertTrue(app.buttons["welcome-start"].waitForExistence(timeout:10));app.buttons["welcome-start"].tap()
        let guest=app.buttons["welcome-guest"];reveal(guest,in:app);guest.tap()
        let recommended=app.buttons["home-recommended"],following=app.buttons["home-following"]
        XCTAssertTrue(recommended.waitForExistence(timeout:10));XCTAssertEqual(recommended.value as? String,"選択中")
        XCTAssertLessThan(recommended.frame.midX,following.frame.midX)
        following.tap();XCTAssertEqual(following.value as? String,"選択中");recommended.tap()
        app.buttons["検索"].firstMatch.tap();XCTAssertTrue(app.textFields["public-search-input"].waitForExistence(timeout:5));capture(app,"UI-09-search-live")
        app.buttons["閉じる"].firstMatch.tap();app.buttons["通知"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["まだお知らせはないよ"].waitForExistence(timeout:5));capture(app,"UI-09-notification-guest")
    }
    func testPetEditAndMemoryRoutes() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-reference-gallery"];app.launch()
        let route=app.buttons["ui-route-03-edit-pet"];reveal(route,in:app);route.tap()
        let name=app.textFields["edit-pet-name"];XCTAssertTrue(name.waitForExistence(timeout:5));name.tap()
        if let current=name.value as? String {name.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:current.count))};name.typeText("Edited pet")
        app.buttons["save-pet-edit"].tap()
        let owner=app.buttons["ui-route-10-owner"];reveal(owner,in:app);XCTAssertTrue(owner.exists);owner.tap()
        let edited=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","Edited pet")).firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout:10))
        capture(app,"UI-03-pet-edit-save")
    }
    func testReferenceHomeFiltersAndProfileNavigation() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_API_BASE"]="http://127.0.0.1:8766"
        app.launch()
        let recommended=app.buttons["home-recommended"],following=app.buttons["home-following"]
        XCTAssertTrue(recommended.waitForExistence(timeout:10));XCTAssertEqual(recommended.value as? String,"選択中")
        XCTAssertLessThan(recommended.frame.midX,following.frame.midX)
        let post=app.buttons["search-open-demo-post-demo-9"]
        capture(app,"Reference-02-discovery-MEFRION")
        app.buttons["home-search"].tap()
        XCTAssertTrue(app.textFields["public-search-input"].waitForExistence(timeout:10))
        XCTAssertTrue(post.waitForExistence(timeout:15))
        app.buttons["犬"].firstMatch.tap()
        XCTAssertFalse(post.exists,"猫の投稿は検索の犬フィルターで表示しない")
        app.buttons["閉じる"].firstMatch.tap()
        app.buttons["フォロー中"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["フォロー中のPetはまだいません"].waitForExistence(timeout:10))
        capture(app,"Reference-02-following-empty")
        app.buttons["root-tab-マイページ"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["あなたのマイページ"].waitForExistence(timeout:5))
        capture(app,"Reference-10-private-mypage")
    }
    func testTwinsCropHistoryAndCameraAvailability() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"];app.launch();app.buttons["root-tab-そっくり"].firstMatch.tap()
        let camera=app.buttons["twins-camera"];XCTAssertTrue(camera.waitForExistence(timeout:5));reveal(camera,in:app);camera.tap()
        let unavailable=app.staticTexts["twins-camera-error"]
        if unavailable.waitForExistence(timeout:3) {app.buttons["カメラの案内を閉じる"].tap()} else {
            let dismissCamera=app.buttons["DismissButton"]
            XCTAssertTrue(dismissCamera.waitForExistence(timeout:10));XCTAssertTrue(app.buttons["PhotoCapture"].exists)
            // Camera availability only: do not capture an unknown/live source.
            dismissCamera.tap()
        }
        app.buttons["twins-demo-image"].tap();let crop=app.buttons["twins-crop"];reveal(crop,in:app);crop.tap()
        XCTAssertTrue(app.images["twins-crop-preview"].waitForExistence(timeout:5));capture(app,"Phase1-Twins-crop-owned-input")
        app.buttons["twins-apply-crop"].tap()
        let consent=app.switches["twins-consent"];reveal(consent,in:app);consent.switches.firstMatch.tap()
        let search=app.buttons["twins-search"];reveal(search,in:app);XCTAssertTrue(search.isEnabled);search.tap()
        XCTAssertTrue(app.staticTexts["twins-processing-duration"].waitForExistence(timeout:30))
        let history=app.buttons["twins-history"]
        for _ in 0..<12 {if history.isHittable && history.frame.minY>=60 && history.frame.maxY<app.frame.height-90 {break};app.swipeDown()};XCTAssertGreaterThanOrEqual(history.frame.minY,60);history.tap()
        XCTAssertTrue(app.navigationBars["検索履歴"].waitForExistence(timeout:10))
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"twins-history-record").firstMatch.waitForExistence(timeout:5));capture(app,"Phase1-Twins-history-owned-candidates")
        let clear=app.buttons["twins-clear-history"];reveal(clear,in:app);clear.tap();app.buttons["検索履歴を削除する"].tap()
        XCTAssertTrue(app.staticTexts["twins-history-empty"].waitForExistence(timeout:5));capture(app,"Phase1-Twins-history-cleared")
    }
    func testFormerProviderCanWithdrawAndDelete() throws {
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("cloud-provider-fixture.json")
        guard let data=try? Data(contentsOf:url) else {throw XCTSkip("Former-provider fixture absent; UI not executed")}
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:String]);let photo=try XCTUnwrap(fixture["photo_id"])
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_CLOUD_PUBLIC_KEY"]=fixture["anon_key"];app.launchEnvironment["MEFRION_TEST_CLOUD_EMAIL"]=fixture["email"];app.launchEnvironment["MEFRION_TEST_CLOUD_PASSWORD"]=fixture["password"]
        app.launch();app.buttons["root-tab-マイページ"].tap()
        let family=app.buttons["open-cloud-family"];XCTAssertTrue(family.waitForExistence(timeout:5));reveal(family,in:app);family.tap()
        XCTAssertTrue(app.staticTexts["cloud-authenticated"].waitForExistence(timeout:30))
        let management=app.buttons["cloud-provider-management"];reveal(management,in:app);management.tap()
        let sns=app.buttons["provider-withdraw-sns"];XCTAssertTrue(sns.waitForExistence(timeout:20));XCTAssertTrue(app.staticTexts["SNS：同意中"].exists)
        XCTAssertFalse(app.images["cloud-photo"].exists);XCTAssertFalse(app.images["cloud-public-image"].exists);capture(app,"Phase4-former-provider-consent-only")
        sns.tap();app.buttons["同意を取り消す"].tap()
        XCTAssertTrue(app.staticTexts["SNS：同意なし"].waitForExistence(timeout:20));XCTAssertTrue(app.staticTexts["Twins：同意中"].exists)
        let delete=app.buttons["provider-delete-"+photo];reveal(delete,in:app);delete.tap();app.buttons["元写真と関連する公開表示を削除"].tap()
        XCTAssertTrue(app.staticTexts["提供した写真はありません。"].waitForExistence(timeout:20));XCTAssertFalse(delete.exists);capture(app,"Phase4-former-provider-deleted")
    }
    func testCloudLikeSaveFollowCommentAndDelete() throws {
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("cloud-safety-fixture.json")
        guard let data=try? Data(contentsOf:url) else {throw XCTSkip("Synthetic social fixture absent; UI not executed")}
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:String])
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_CLOUD_PUBLIC_KEY"]=fixture["anon_key"];app.launchEnvironment["MEFRION_TEST_CLOUD_EMAIL"]=fixture["email"];app.launchEnvironment["MEFRION_TEST_CLOUD_PASSWORD"]=fixture["password"]
        app.launch();app.buttons["root-tab-マイページ"].firstMatch.tap()
        let family=app.buttons["open-cloud-family"];XCTAssertTrue(family.waitForExistence(timeout:5));reveal(family,in:app);family.tap()
        XCTAssertTrue(app.staticTexts["cloud-authenticated"].waitForExistence(timeout:30))
        app.buttons["root-tab-ホーム"].firstMatch.tap();let cloud=app.buttons["open-cloud-discovery"];reveal(cloud,in:app);cloud.tap()
        XCTAssertTrue(app.images["cloud-public-image"].waitForExistence(timeout:30))
        let like=app.buttons["cloud-like-post"].firstMatch;reveal(like,in:app);like.tap()
        expectation(for:NSPredicate(format:"value == %@", "いいね済み"),evaluatedWith:like);waitForExpectations(timeout:30)
        let saved=app.buttons["cloud-save-post"].firstMatch;reveal(saved,in:app);saved.tap();expectation(for:NSPredicate(format:"value == %@", "保存済み"),evaluatedWith:saved);waitForExpectations(timeout:30)
        let follow=app.buttons["cloud-follow-pet"].firstMatch;reveal(follow,in:app);follow.tap()
        let following=NSPredicate(format:"label == %@", "解除");expectation(for:following,evaluatedWith:follow);waitForExpectations(timeout:30)
        let comments=app.buttons["cloud-comments-post"].firstMatch;reveal(comments,in:app);comments.tap()
        let field=app.descendants(matching:.any)["cloud-comment-body"];XCTAssertTrue(field.waitForExistence(timeout:30));reveal(field,in:app);field.tap();field.typeText("Native synthetic comment only")
        app.buttons["cloud-comment-done"].tap();let send=app.buttons["cloud-send-comment"];reveal(send,in:app);send.tap()
        let posted=app.staticTexts["Native synthetic comment only"];for _ in 0..<8 {if posted.exists {break};app.swipeDown()};XCTAssertTrue(posted.waitForExistence(timeout:30));capture(app,"Phase3-real-cloud-comment")
        let actions=app.buttons["コメントの操作"].firstMatch;reveal(actions,in:app);actions.tap()
        app.buttons["cloud-delete-comment"].firstMatch.tap();app.buttons["コメントを削除"].tap()
        XCTAssertTrue(app.staticTexts["コメントは削除されました"].waitForExistence(timeout:30));capture(app,"Phase3-cloud-comment-deleted")
        app.buttons["閉じる"].tap()
    }
    func testCloudPublicImageReportBlockAndUnblock() throws {
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("cloud-safety-fixture.json")
        guard let data=try? Data(contentsOf:url) else {throw XCTSkip("Synthetic public safety fixture absent; UI not executed")}
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:String])
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_CLOUD_PUBLIC_KEY"]=fixture["anon_key"];app.launchEnvironment["MEFRION_TEST_CLOUD_EMAIL"]=fixture["email"];app.launchEnvironment["MEFRION_TEST_CLOUD_PASSWORD"]=fixture["password"]
        app.launch();app.buttons["root-tab-マイページ"].tap()
        let family=app.buttons["open-cloud-family"];XCTAssertTrue(family.waitForExistence(timeout:5));reveal(family,in:app);family.tap()
        XCTAssertTrue(app.staticTexts["cloud-authenticated"].waitForExistence(timeout:30))
        app.buttons["root-tab-ホーム"].tap()
        let cloud=app.buttons["open-cloud-discovery"];XCTAssertTrue(cloud.waitForExistence(timeout:10));reveal(cloud,in:app);cloud.tap()
        let image=app.images["cloud-public-image"];XCTAssertTrue(image.waitForExistence(timeout:30));capture(app,"Phase4-real-cloud-public-derivative")
        let report=app.buttons["cloud-report-post"].firstMatch;reveal(report,in:app);report.tap()
        let submit=app.buttons["cloud-submit-report"];XCTAssertTrue(submit.waitForExistence(timeout:10));reveal(submit,in:app);submit.tap()
        XCTAssertTrue(app.staticTexts["cloud-report-success"].waitForExistence(timeout:20));capture(app,"Phase4-cloud-report-received")
        app.buttons["閉じる"].tap()
        let block=app.buttons["cloud-block-post"].firstMatch;reveal(block,in:app);block.tap();app.buttons["相手のすべてのPetをブロック"].tap()
        let empty=app.staticTexts["公開された投稿はまだありません"];XCTAssertTrue(empty.waitForExistence(timeout:30));XCTAssertFalse(image.exists);capture(app,"Phase4-cloud-blocked-feed")
        if !app.buttons["ブロックした相手"].isHittable {app.swipeDown()};app.buttons["ブロックした相手"].tap()
        let unblock=app.buttons["解除する"];XCTAssertTrue(unblock.waitForExistence(timeout:20));unblock.tap()
        XCTAssertTrue(app.staticTexts["ブロックした相手はいません"].waitForExistence(timeout:20))
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.buttons["最新の公開投稿を取得"].tap();XCTAssertTrue(image.waitForExistence(timeout:30));capture(app,"Phase4-cloud-unblocked-feed")
    }
    func testCloudPublicationConsentPendingAndWithdrawal() throws {
        let fixtureURL=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("cloud-fixture.json")
        guard let data=try? Data(contentsOf:fixtureURL) else {throw XCTSkip("Private cloud fixture absent; publication UI not executed")}
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:String]);let pet=try XCTUnwrap(fixture["pet_id"])
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_CLOUD_PUBLIC_KEY"]=fixture["anon_key"];app.launchEnvironment["MEFRION_TEST_CLOUD_EMAIL"]=fixture["email"];app.launchEnvironment["MEFRION_TEST_CLOUD_PASSWORD"]=fixture["password"]
        app.launch();app.buttons["root-tab-マイページ"].tap()
        let family=app.buttons["open-cloud-family"];XCTAssertTrue(family.waitForExistence(timeout:5));reveal(family,in:app);family.tap()
        XCTAssertTrue(app.staticTexts["cloud-authenticated"].waitForExistence(timeout:30));app.buttons["cloud-pet-"+pet].tap()
        let upload=app.buttons["cloud-upload-demo"];XCTAssertTrue(upload.waitForExistence(timeout:10));reveal(upload,in:app);upload.tap()
        XCTAssertTrue(app.images["cloud-photo"].waitForExistence(timeout:30))
        let albumSettings=app.buttons["アルバムの設定"];reveal(albumSettings,in:app);albumSettings.tap()
        let compose=app.buttons["cloud-compose-post"];reveal(compose,in:app);compose.tap()
        let select=app.buttons["cloud-publication-select"].firstMatch;XCTAssertTrue(select.waitForExistence(timeout:10));select.tap()
        let field=app.descendants(matching:.any).matching(identifier:"cloud-publication-body").firstMatch;reveal(field,in:app);field.tap();field.typeText("Synthetic native publication test")
        let done=app.buttons["cloud-publication-done"];XCTAssertTrue(done.waitForExistence(timeout:5));done.tap()
        let request=app.buttons["cloud-request-publication"];XCTAssertFalse(request.isEnabled)
        let provider=app.switches["cloud-provider-consent"];reveal(provider,in:app);provider.switches.firstMatch.tap()
        XCTAssertEqual(provider.value as? String,"1")
        XCTAssertFalse(request.isEnabled)
        let consent=app.switches["cloud-publication-consent"];reveal(consent,in:app);consent.switches.firstMatch.tap()
        XCTAssertEqual(consent.value as? String,"1");XCTAssertTrue(request.isEnabled)
        reveal(request,in:app);request.tap()
        let status=app.staticTexts["cloud-publication-status"];reveal(status,in:app);XCTAssertTrue(status.waitForExistence(timeout:30))
        XCTAssertEqual(status.label,"公開用画像を処理待ちです");capture(app,"Phase3-cloud-publication-pending")
        let stop=app.buttons["cloud-stop-publication"];reveal(stop,in:app);stop.tap()
        expectation(for:NSPredicate(format:"label == %@","公開を停止しました"),evaluatedWith:status);waitForExpectations(timeout:15)
        capture(app,"Phase3-cloud-publication-withdrawn");app.buttons["閉じる"].tap()
        let moreSettings=app.buttons["その他の管理"];reveal(moreSettings,in:app);moreSettings.tap()
        let stopProfile=app.buttons["cloud-stop-public-profile"];if !stopProfile.isHittable {app.swipeDown()};stopProfile.tap();app.buttons["公開プロフィールを停止"].tap()
        let refresh=app.buttons["cloud-refresh-album"];reveal(refresh,in:app);refresh.tap()
        XCTAssertTrue(app.images["cloud-photo"].waitForExistence(timeout:30));let photoActions=app.buttons["写真の操作"].firstMatch;reveal(photoActions,in:app);photoActions.tap();let delete=app.buttons["cloud-delete-photo"].firstMatch;reveal(delete,in:app);delete.tap();app.buttons["削除する"].tap()
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.images["cloud-photo"]);waitForExpectations(timeout:30)
    }
    func testRealCloudFamilyLoginUploadAndDelete() throws {
        let fixtureURL=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("cloud-fixture.json")
        guard let data=try? Data(contentsOf:fixtureURL) else {throw XCTSkip("Private cloud fixture is absent; cloud E2E not executed")}
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:String])
        let pet=try XCTUnwrap(fixture["pet_id"])
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_CLOUD_PUBLIC_KEY"]=fixture["anon_key"]
        app.launchEnvironment["MEFRION_TEST_CLOUD_EMAIL"]=fixture["email"]
        app.launchEnvironment["MEFRION_TEST_CLOUD_PASSWORD"]=fixture["password"]
        app.launchEnvironment["MEFRION_TEST_EXPIRE_SESSION"]="1"
        app.launch()
        app.buttons["root-tab-マイページ"].tap()
        let family=app.buttons["open-cloud-family"];XCTAssertTrue(family.waitForExistence(timeout:5));reveal(family,in:app);family.tap()
        XCTAssertTrue(app.staticTexts["cloud-authenticated"].waitForExistence(timeout:30))
        let entry=app.buttons["cloud-pet-"+pet];XCTAssertTrue(entry.waitForExistence(timeout:10));entry.tap()
        let upload=app.buttons["cloud-upload-demo"];XCTAssertTrue(upload.waitForExistence(timeout:10));upload.tap()
        let photo=app.images["cloud-photo"];XCTAssertTrue(photo.waitForExistence(timeout:30))
        capture(app,"Phase2-real-server-private-photo")
        let photoActions=app.buttons["写真の操作"].firstMatch;reveal(photoActions,in:app);photoActions.tap()
        let delete=app.buttons["cloud-delete-photo"];reveal(delete,in:app);delete.tap()
        app.buttons["削除する"].tap()
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:photo)
        waitForExpectations(timeout:30)
        capture(app,"Phase2-real-server-deleted-photo")
    }
    func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 { if element.isHittable { return }; app.swipeUp() }
    }

    func testLocalSocialLikeAndCommentThroughAPI() throws {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test-isolated"]
        app.launchEnvironment["MEFRION_TEST_API_BASE"]="http://127.0.0.1:8766"
        app.launch()
        let like=app.buttons["feed-like-demo-post-demo-9"]
        XCTAssertTrue(like.waitForExistence(timeout:15));reveal(like,in:app);like.tap()
        let liked=NSPredicate(format:"label == %@","いいね 1件")
        expectation(for:liked,evaluatedWith:like)
        waitForExpectations(timeout:10)
        let open=app.buttons["feed-open-demo-post-demo-9"]
        if !open.isHittable { app.swipeDown() };open.tap()
        let field=app.descendants(matching:.any).matching(identifier:"comment-input").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout:5));reveal(field,in:app);field.tap();field.typeText("UI API test comment")
        let send=app.buttons["送信する"];reveal(send,in:app);send.tap()
        XCTAssertTrue(app.staticTexts["UI API test comment"].waitForExistence(timeout:10))
        capture(app,"Phase3-actual-api-comment")
    }
    func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testUnifiedNotificationSettingsAndCuteInbox() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated","--ui-notifications"];app.launch()
        app.buttons["通知設定"].tap()
        XCTAssertTrue(app.staticTexts["家族アルバム"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["こむぎ"].exists)
        XCTAssertTrue(app.staticTexts["新しい写真・動画"].firstMatch.exists)
        XCTAssertFalse(app.buttons["設定を保存"].exists)
        XCTAssertFalse(app.staticTexts["Twinsのクラウド通知は準備中です。"].exists)
        XCTAssertFalse(app.staticTexts["アプリ内通知の表示を設定します。プッシュ通知はまだ接続していません。家族アルバムの通知設定は別です。"].exists)
        let like=app.switches["notice-setting-like"]
        XCTAssertTrue(like.exists);like.tap();XCTAssertEqual(like.value as? String,"0")
        let pause=app.switches["しばらくおやすみ"].firstMatch
        reveal(pause,in:app);pause.tap()
        XCTAssertTrue(app.staticTexts["いつまで？"].waitForExistence(timeout:5))
        capture(app,"Unified-notification-settings")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["お知らせ"].tap()
        XCTAssertTrue(app.staticTexts["アルバムに4枚の思い出が増えたよ"].waitForExistence(timeout:10))
        capture(app,"Cute-notification-inbox")
        app.buttons["notice-filter-family"].tap()
        XCTAssertFalse(app.staticTexts["こむぎの投稿にいいね ♡"].exists)
        XCTAssertTrue(app.staticTexts["もち"].exists)
        capture(app,"Cute-family-notifications")
    }

    func testBreedAutocompleteSelectsCanonicalName() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-test-isolated"];app.launch()
        app.buttons["root-tab-投稿"].tap()
        app.buttons["create-pet"].tap()
        let breed=app.textFields["犬種"]
        XCTAssertTrue(breed.waitForExistence(timeout:10))
        reveal(breed,in:app);breed.tap();breed.typeText("といぷー")
        let choice=app.buttons["breed-suggestion-トイ・プードル"]
        XCTAssertTrue(choice.waitForExistence(timeout:5))
        choice.tap()
        XCTAssertEqual(breed.value as? String,"トイ・プードル")
    }
    func testFourTabsPrivateAlbumComparisonAndTwinsStates() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-isolated"]; app.launch()
        XCTAssertTrue(app.buttons["root-tab-ホーム"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["MEFRION"].exists)
        for tab in ["ホーム", "そっくり", "投稿", "マイページ"] {
            XCTAssertTrue(app.buttons["root-tab-"+tab].exists)
        }
        capture(app, "Phase0-home-four-tabs")
        app.buttons["root-tab-投稿"].tap()
        app.buttons["create-pet"].tap()
        let name = app.textFields["pet-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("こむぎ")
        let dogChoice=app.buttons["pet-species-dog"];reveal(dogChoice,in:app);dogChoice.tap()
        let breed=app.textFields["private-pet-breed"]
        reveal(breed,in:app);breed.tap();breed.typeText("柴犬")
        app.buttons["save-private-pet"].tap()
        XCTAssertTrue(app.buttons["demo-photos"].waitForExistence(timeout: 5))
        app.buttons["demo-photos"].tap()
        let save = app.buttons["save-private-album"]
        reveal(save, in: app)
        XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
        let viewAlbum = app.buttons["open-album"]
        if !viewAlbum.isHittable { app.swipeUp() }
        viewAlbum.tap()
        XCTAssertTrue(app.staticTexts["家族内のみ・非公開"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2020"].exists)
        capture(app, "Phase1-private-album")
        let first = app.buttons.matching(identifier: "compare-select").element(boundBy: 0)
        first.tap()
        let second = app.buttons.matching(identifier: "compare-select").element(boundBy: 1)
        if !second.isHittable { app.swipeUp() }; second.tap()
        let compare = app.buttons["open-comparison"]
        if !compare.isHittable { app.swipeUp() }; compare.tap()
        let saveCard = app.buttons["save-private-card"]
        if !saveCard.isHittable { app.swipeUp() }
        saveCard.tap()
        XCTAssertTrue(app.staticTexts["非公開で保存しました。"].waitForExistence(timeout: 5))
        capture(app, "Phase1-private-card")
        app.buttons["root-tab-そっくり"].tap()
        app.buttons["twins-demo-image"].tap()
        let consent = app.switches["twins-consent"]
        if !consent.isHittable { app.swipeUp() }; consent.tap()
        let search = app.buttons["twins-search"]
        if !search.isHittable { app.swipeUp() }; search.tap()
        // On-device demo candidates may be below threshold; do not fabricate a full result.
        XCTAssertTrue(app.buttons["twins-discard"].waitForExistence(timeout: 30))
        capture(app, "Phase1-twins-on-device-demo")
        app.buttons["twins-discard"].tap()
    }
}
