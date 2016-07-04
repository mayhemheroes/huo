#include <stdbool.h>
#include "../structures/structures.h"
#include "../execute.h"
#include "../base_util.h"
#include "../core_functions.h"
#include "let_binding.h"
#include "for_each.h"
#include "../config.h"

struct Value for_each(struct Tree * ast, hash_table * defined, struct Scopes * scopes, int max_depth){
    if (max_depth <= 0) {
        ERROR("Max depth exceeded in computation");
    }
    bool use_index;
    int func_index;
    if (ast->size == 4) {
        use_index = true;
        func_index = 3;
    } else if (ast->size == 3) {
        use_index = false;
        func_index = 2;
    } else {
        ERROR("Wrong number of arguments for for_each: %i != [3,4]\n", ast->size);
    }
    struct Value array = execute(ast->children[0], defined, scopes, max_depth - 1);
    if(array.type == STRING){
        return for_each_string(value_as_string(&array), ast, defined, scopes, max_depth);
    } else if (array.type == ARRAY) {
        for(int i = 0; i < array.data.array->size; i++){
            struct Value *item = value_copy_heap(array.data.array->values[i]);
            struct Tree * function = duplicate_tree(ast->children[func_index]);
            store_let_value(&ast->children[1]->content, item, scopes);
            if (use_index) {
                struct Value index = value_from_long(i);
                store_let_value(&ast->children[2]->content, &index, scopes);
            }
            execute(function, defined, scopes, max_depth - 1);
        }
        return array;
    } else {
        ERROR("Invalid type for for_each iterable: '%c' != ARRAY", array.type);
    }
}

struct Value for_each_string(struct String string, struct Tree * ast, hash_table * defined, struct Scopes * scopes, int max_depth){
    bool use_index;
    int func_index;
    if (ast->size == 4) {
        use_index = true;
        func_index = 3;
    } else if (ast->size == 3) {
        use_index = false;
        func_index = 2;
    } else {
        ERROR("Wrong number of arguments for for_each: %i != [3,4]\n", ast->size);
    }
    for(int i = 0; i < string.length; i++){
        struct String item = string_substring(i, i+1, string);
        struct Value item_val = value_from_string(string_copy_stack(&item));
        struct Tree * function = duplicate_tree(ast->children[func_index]);
        store_let_value(&ast->children[1]->content, &item_val, scopes);
        if (use_index) {
            struct Value index = value_from_long(i);
            store_let_value(&ast->children[2]->content, &index, scopes);
        }
        execute(function, defined, scopes, max_depth - 1);
    }
    return value_from_string(string);
}
