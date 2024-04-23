/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.apache.fontbox.ttf.gsub;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import java.util.StringJoiner;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * Takes in the given text having compound-glyphs to substitute, and splits it into chunks consisting of parts that
 * should be substituted and the ones that can be processed normally.
 *
 * @author Palash Ray
 */
public class CompoundCharacterTokenizer {
    private static final String GLYPH_ID_SEPARATOR = "_";
    private final List<Pattern> regexExpressions;


    /**
     * Constructor. Calls getRegexFromTokens which returns strings like
     * (_79_99_)|(_80_99_)|(_92_99_) and creates a regexp assigned to regexExpression. See the code
     * in GlyphArraySplitterRegexImpl on how these strings were created.
     *
     * @param compoundWords A set of strings like _79_99_, _80_99_ or _92_99_ .
     */
    public CompoundCharacterTokenizer(Set<String> compoundWords) {
        validateCompoundWords(compoundWords);
        String tokens = getRegexFromTokens(compoundWords);
        regexExpressions = Stream.of(tokens.split("\\|"))
                .map(token -> "^" + token) // We want to match the token at the beginning of the input text
                .map(Pattern::compile).collect(Collectors.toList());
    }

    private void validateCompoundWords(Set<String> compoundWords) {
        if (compoundWords == null || compoundWords.isEmpty()) {
            throw new IllegalArgumentException("Compound words cannot be null or empty");
        }

        // Ensure all word are starting and ending with the GLYPH_ID_SEPARATOR
        compoundWords.forEach(word -> {
            if (!word.startsWith(GLYPH_ID_SEPARATOR) || !word.endsWith(GLYPH_ID_SEPARATOR)) {
                throw new IllegalArgumentException("Compound words should start and end with " + GLYPH_ID_SEPARATOR);
            }
        });
    }

    /**
     * For each regex expression, check if we have a match, if we do, we remove that match from the input text and continue until we processed the whole input text
     */
    public List<String> tokenize(String text) {
        String inputText = text;
        List<String> tokens = new ArrayList<>();
        if (inputText == null) {
            return tokens;
        }

        StringBuilder currentTokens = new StringBuilder();
        while (!inputText.isEmpty()) {
            boolean foundMatch = false;
            for (Pattern regexExpression : regexExpressions) {
                Matcher regexMatcher = regexExpression.matcher(inputText);
                while (regexMatcher.find()) {
                    // If we found a match for that group, we add the text before the match, the match itself
                    // Then we updated the input text to remove the match
                    foundMatch = true;
                    tokens.add(appendGlyphSeparatorIfMissing(prependGlyphSeparatorIfMissing(currentTokens.toString())));
                    currentTokens = new StringBuilder();

                    int startIndex = regexMatcher.start();
                    if (startIndex > 0) {
                        tokens.add(inputText.substring(0, startIndex));
                    }
                    tokens.add(regexMatcher.group());
                    inputText = getRemainingText(inputText, regexMatcher.end());
                }
            }

            // If we haven't found any match, we add the first glyph to the tokens and move to the next set of letters
            if (!foundMatch) {
                int endIndex = inputText.indexOf(GLYPH_ID_SEPARATOR, 1);
                if (endIndex == -1) {
                    endIndex = inputText.length();
                }
                String token = inputText.substring(0, endIndex);
                currentTokens.append(token);
                inputText = getRemainingText(inputText, endIndex);
            }
        }

        if (currentTokens.length() > 0) {
            tokens.add(appendGlyphSeparatorIfMissing(prependGlyphSeparatorIfMissing(currentTokens.toString())));
        }

        return tokens.stream()
                .filter(token -> !token.isEmpty())
                .filter(token -> !GLYPH_ID_SEPARATOR.equals(token))
                .collect(Collectors.toList());
    }

    private String getRemainingText(String inputText, int endIndex) {
        inputText = inputText.substring(endIndex);

        if (!inputText.isEmpty()) {
            // Make sure we keep the _ pattern at the beginning and end of the input text
            inputText = appendGlyphSeparatorIfMissing(prependGlyphSeparatorIfMissing(inputText));
        }
        return inputText;
    }

    private String getRegexFromTokens(Set<String> compoundWords) {
        StringJoiner sj = new StringJoiner(")|(", "(", ")");
        compoundWords.forEach(sj::add);
        return sj.toString();
    }

    private String appendGlyphSeparatorIfMissing(final String str) {
        if (str == null || str.endsWith(CompoundCharacterTokenizer.GLYPH_ID_SEPARATOR)) {
            return str;
        }

        return str + CompoundCharacterTokenizer.GLYPH_ID_SEPARATOR;
    }

    private String prependGlyphSeparatorIfMissing(final String str) {
        if (str == null || str.startsWith(CompoundCharacterTokenizer.GLYPH_ID_SEPARATOR)) {
            return str;
        }

        return CompoundCharacterTokenizer.GLYPH_ID_SEPARATOR + str;
    }

}
