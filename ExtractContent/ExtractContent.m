//
//  ExtractContent.m
//  Osaki
//
//  Created by Tomoya_Hirano on 5/3/15.
//  Copyright (c) 2015 Tomoya_Hirano. All rights reserved.
//

#import "ExtractContent.h"
#import "RegexKitLite.h"

@interface ExtractContent (){
    /* Default option parameters. */
    int threshold;
    int min_length;
    double decay_factor;
    double continuous_factor;
    int punctuation_weight;
    NSString *punctuations;
    NSString *waste_expressions;
    NSString *dom_separator;
    BOOL debug;
    /* 実体参照変換 */
    NSDictionary* CHARREF;
}
@end

@implementation ExtractContent

- (instancetype)init{
    self = [super init];
    if (self) {
        /* Default option parameters. */
        threshold = 100;
        min_length = 80;
        decay_factor = 0.73;
        continuous_factor = 1.62;
        punctuation_weight = 10;
        punctuations = @"([、。，．！？]|\\.[^A-Za-z0-9]|,[^0-9]|!|\\?)";
        waste_expressions = @"(?i)Copyright|All Rights Reserved";
        dom_separator = @"";
        debug = false;
        /* 実体参照変換 */
        CHARREF = @{@"&nbsp;"  :@" ",
                    @"&nbsp;"  :@" ",
                    @"&gt;"    :@">",
                    @"&amp;"   :@"&",
                    @"&laquo;" :@"0xC2 0xAB",
                    @"&raquo;" :@"0xC2 0xBB"};
    }
    return self;
}

- (NSString*)analyse:(NSString*)html{
//    NSString*title = [self extract_title:html];
    //余分なタグを除去する
    html = [self eliminate_useless_tags:html];
    
    double factor = 1.0;
    double continuous = 1.0;
    NSString *body = @"";
    int score = 0;
    
    
    NSMutableArray*bodylist = [NSMutableArray array];
    NSArray* list = [html componentsSeparatedByRegex:@"(?s)<\\/?(?:div|center|td)[^>]*>|<p\\s*[^>]*class\\s*=\\s*[\"']?(?:posted|plugin-\\w+)['\"]?[^>]*>"];
    for(NSString* _block in list){
        NSString*block = _block;
        if([block isEqualToString:@""]){
            continue;
        }
        block = [self strip:block];
        if([self has_only_tags:block]){
            continue;
        }
        if(body.length > 0){
            continuous = continuous /continuous_factor;
        }
        //リンク除外＆リンクリスト判定
        NSString *notelinked = [self eliminate_link:block];
        if( notelinked.length < min_length){
            continue;
        }
        //スコア算出
        double c = (notelinked.length + [self scan:notelinked pattern:punctuations].count * punctuation_weight) * factor;
        factor *= decay_factor;
        double not_body_rate = [self scan:block pattern:waste_expressions].count + [self scan:block pattern:@"(?i)amazon[a-z0-9\\.\\/\\-\\?&]+-22"].count / 2.0;
        if (not_body_rate>0){
            c *= pow(0.72, not_body_rate);
        };
        double c1 = c * continuous;
        if(c1 > threshold){
            body = [body stringByAppendingString:[block stringByAppendingString:@"\n"]];
            score += c1;
            continuous = continuous_factor;
        }else if(c > threshold){
            [bodylist addObject:@{@"body":body,@"score":[NSNumber numberWithInt:score]}];
            body = [body stringByAppendingString:[block stringByAppendingString:@"\n"]];
            score = (int)c;
            continuous = continuous_factor;
        }
        
    }
    [bodylist addObject:@{@"body":body,@"score":[NSNumber numberWithInt:score]}];
    
    //一番スコアの高いものを採用
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"score" ascending:true];
    NSArray *sortarray = [NSArray arrayWithObject:sortDescriptor];
    NSArray *resultarray = [bodylist sortedArrayUsingDescriptors:sortarray];
    
    return [self strip_tags:[resultarray firstObject][@"body"]];
}


/**
 *  linkを除去します
 *
 *  @param html htmlの文字列
 *
 *  @return 除去後の文字列
 */
- (NSString*)eliminate_link:(NSString*)html{
    int count = 0;
    NSString*notlinked = html;
    for (NSArray*array in [html arrayOfCaptureComponentsMatchedByRegex:@"(?i)(?s)<a\\s[^>]*>.*?<\\/a\\s*>"]) {
        count++;
        NSString*hit = array[0];
        notlinked = [notlinked stringByReplacingOccurrencesOfString:hit withString:@""];
    }
    notlinked = [notlinked stringByReplacingOccurrencesOfRegex:@"(?i)(?s)<form\\s[^>]*>.*?<\\/form\\s*>" withString:@""];
    notlinked = [self strip_tags:notlinked];
    if (notlinked.length < 20 * count || [self islinklist:html]) {
        return @"";
    }
    return notlinked;
}

/**
 *  リンクリストかどうか確認します。
 *
 *  @param st htmlの文字列
 *
 *  @return 真偽値
 */
- (BOOL)islinklist:(NSString*)st{
    NSArray*m = [st captureComponentsMatchedByRegex:@"(?s)(?i)<(?:ul|dl|ol)(.+?)<\\/(?:ul|dl|ol)>"];
    if (m.count>0) {
        NSString *listpart = @"";
        listpart = m[1];
        NSString *outside = @"";
        outside = [st stringByReplacingOccurrencesOfRegex:@"(?i)(?s)<(?:ul|dl)(.+?)<\\/(?:ul|dl)>" withString:@""];
        outside = [outside stringByReplacingOccurrencesOfRegex:@"(?s)<.+?>" withString:@""];
        outside = [outside stringByReplacingOccurrencesOfRegex:@"//s+" withString:@""];
        NSArray* list = [listpart componentsSeparatedByRegex:@"<li[^>]*>"];
        NSMutableArray* m_list = [NSMutableArray arrayWithArray:list];
        [m_list removeObjectAtIndex:0];
        int rate = [self evaluate_list:m_list.copy];
        return (outside.length <= st.length / (45.0 / rate));
    }
    return false;
}


/**
 *  評価関数：
 *
 *  @param list_array
 *
 *  @return
 */
- (int)evaluate_list:(NSArray*)list_array{
    if(list_array.count == 0){
        return 1;
    }
    int hit = 0;
    for(NSString *list in list_array){
        if([list isMatchedByRegex:@"(?i)(?s)<a\\s+href=(['\"]?)([^\"'\\s]+)\\1"]){
            hit++;
        }
    }
    return 9 * (1 * hit / list_array.count) * 9 * (1 * hit / list_array.count) + 1;
}

/**
 *  文字列がタグだけで構成されているかどうかを確認します。
 *
 *  @param st htmlの文字列
 *
 *  @return タグだけで構成されている場合、真偽値で正を返します。
 */
- (BOOL)has_only_tags:(NSString *)st{
    st = [st stringByReplacingOccurrencesOfRegex:@"(?i)(?s)<[^>]*>" withString:@""];
    st = [st stringByReplacingOccurrencesOfRegex:@"&nbsp;" withString:@""];
    return [self strip:st].length == 0;
}

/**
 *  不要なタグを除去します
 *
 *  @param html htmlの文字列
 *
 *  @return 除去後の文字列
 */
- (NSString*)eliminate_useless_tags:(NSString*)html{
    NSMutableArray*removeStrings = [NSMutableArray array];
    [removeStrings addObject:@"<!--(.|\n)*?-->"];
    [removeStrings addObject:@"(?i)(?s)<script[^>]*?>[\\s\\S]*?<\\/script>"];
    [removeStrings addObject:@"(?i)(?s)<select[^>]*?>[\\s\\S]*?<\\/select>"];
    [removeStrings addObject:@"(?i)(?s)<noscript[^>]*?>[\\s\\S]*?<\\/noscript>"];
    [removeStrings addObject:@"(?i)(?s)<style[^>]*?>[\\s\\S]*?<\\/style>"];
    [removeStrings addObject:@"(?s)<!--.*?-->"];
    for (NSString* removeString in removeStrings) {
        html = [html stringByReplacingOccurrencesOfRegex:removeString withString:@"" options:RKLCaseless range:NSMakeRange(0, html.length) error:nil];
    }
    return html;
}


/**
 *  htmlの文字列からタイトルを取得します。見つからなかった場合は空の文字列を返します。
 *
 *  @param st html文字列
 *
 *  @return タイトルの文字列
 */
- (NSString*)extract_title:(NSString*)st{
    NSArray* m = [st captureComponentsMatchedByRegex:@"(?i)<title[^>]*>\\s*(.*?)\\s*<\\/title\\s*>"];
    if(m){
        return [self strip_tags:m[1]];
    }else{
        return @"";
    }
}

/**
 *  文字列からタグを除去します。
 *
 *  @param html タグの含まれたhtml文字列
 *
 *  @return 処理後の文字列
 */
- (NSString*)strip_tags:(NSString*)html{
    return [html stringByReplacingOccurrencesOfRegex:@"(?s)<.+?>" withString:@""];
}

/**
 *  下記はrubyのメソッドを再現した関数群です。
 */

/**
 *  scanメソッドは、引数で指定した正規表現のパターンとマッチする部分を文字列からすべて取り出し、配列にして返します。マッチする部分がなければ、空の配列を返します。
 *
 *  @param str     検索元文字列
 *  @param pattern 正規表現文字列
 *
 *  @return マッチした文字列配列
 */
- (NSArray*)scan:(NSString*)str pattern:(NSString*)pattern{
    NSArray*m = [str arrayOfCaptureComponentsMatchedByRegex:pattern];
    NSMutableArray*res = [NSMutableArray new];
    for (NSArray*array in m) {
        [res addObject:array[0]];
    }
    return res;
}

/**
 *  stripメソッドは、文字列の先頭と末尾の空白文字を除去した新しい文字列を返します。
 *
 *  @param str 処理にかける文字列
 *
 *  @return 処理後の文字列
 */
- (NSString*)strip:(NSString*)str{
    NSInteger i;
    for(i=0;i<str.length;i++){
        if(![[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[str characterAtIndex:i]]){
            break;
        }
    }
    str = [str stringByReplacingCharactersInRange:NSMakeRange(0, i) withString:@""];
    for(i=str.length-1;i>0;i--){
        if(![[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[str characterAtIndex:i]]){
            break;
        }
    }
    return [str stringByReplacingCharactersInRange:NSMakeRange(i+1, str.length-1-i) withString:@""];
}
@end
