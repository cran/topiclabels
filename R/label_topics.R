#' @title Automatically label topics using language models based on top terms
#'
#' @description
#' Performs an automated labeling process of topics from topic models using
#' language models. For this, the top terms and (optionally) a short context
#' description are used.
#'
#' @details
#' The function builds helpful prompts based on the top terms and sends these
#' prompts to language models on Huggingface. The output is in turn
#' post-processed so that the labels for each topic are extracted automatically.
#' If the automatically extracted labels show any errors, they can alternatively
#' be extracted using custom functions or manually from the original output of
#' the model using the \code{model_output} entry of the lm_topic_labels object.
#'
#' Implemented default parameters for the models \code{HuggingFaceH4/zephyr-7b-beta},
#' \code{tiiuae/falcon-7b-instruct}, and \code{mistralai/Mixtral-8x7B-Instruct-v0.1} are:
#' \describe{
#'   \item{\code{max_new_tokens}}{300}
#'   \item{\code{return_full_text}}{\code{FALSE}}
#' }
#'
#' Implemented prompt types are:
#' \describe{
#'   \item{\code{json}}{the language model is asked to respond in JSON format
#'   with a single field called 'label', specifying the best label for the topic}
#'   \item{\code{plain}}{the language model is asked to return an answer that
#'   should only consist of the best label for the topic}
#'   \item{\code{json-roles}}{the language model is asked to respond in JSON format
#'   with a single field called 'label', specifying the best label for the topic;
#'   in addition, the model is queried using identifiers for <|user|> input and
#'   the beginning of the <|assistant|> output}
#' }
#'
#' @param terms [\code{list (k) of character}]\cr
#' List (each list entry represents one topic) of \code{character} vectors
#' containing the top terms representing the topics that are to be labeled.
#' If a single \code{character} vector is passed, this is interpreted as
#' the top terms of a single topic. If a \code{character} matrix is passed,
#' each column is interpreted as the top terms of a topic.
#' The outputs of the packages \code{stm} (\code{label_topics} object, please
#' specify the type of output using the parameter \code{stm_type}) and the
#' \code{BTM} package (\code{list} of \code{data.frame}s with entries
#' \code{token} and \code{probability} each) are also supported.
#' @param model [\code{character(1)}]\cr
#' Optional.\cr
#' The language model to use for labeling the topics.
#' The model must be accessible via the Huggingface API. Default is
#' \code{mistralai/Mixtral-8x7B-Instruct-v0.1}. Other promising models are
#' \code{HuggingFaceH4/zephyr-7b-beta} or \code{tiiuae/falcon-7b-instruct}.
#' To find more models see: https://huggingface.co/models?other=conversational&sort=likes.
#' @param params [\code{named list}]\cr
#' Optional.\cr
#' Model parameters to pass. Default parameters for common models are
#' given in the details section.
#' @param token [\code{character(1)}]\cr
#' Optional.\cr
#' If you want to address the Huggingface API with a Huggingface token, enter
#' it here. The main advantage of this is a higher rate limit.
#' @param context [\code{character(1)}]\cr
#' Optional.\cr
#' Explanatory context for the topics to be labeled. Using a (very) brief
#' explanation of the thematic context may greatly improve the usefulness of
#' automatically generated topic labels.
#' @param sep_terms [\code{character(1)}]\cr
#' How should the top terms of a single topic be separated in the generated
#' prompts? Default is separation via semicolon and space.
#' @param max_length_label [\code{integer(1)}]\cr
#' What is the maximum number of words a label should consist of? Default is five words.
#' @param prompt_type [\code{character(1)}]\cr
#' Which prompt type should be applied. We implemented various prompt types that
#' differ mainly in how the response of the language model is requested. Examples
#' are given in the details section. Default is the request of a json output.
#' @param stm_type [\code{character(1)}]\cr
#' For stm topics, which type of word weighting should be used? Default is "prob".
#' @param max_wait [\code{integer(1)}]\cr
#' In the case that the rate limit on Huggingface is reached: How long
#' (in minutes) should the system wait until it asks the user whether
#' to continue (in other words: to wait). The default is zero minutes, i.e the
#' user is asked every time the rate limit is reached.
#' @param progress [\code{logical(1)}]\cr
#' Should a nice progress bar be shown? Turning it off, could lead to
#' significantly faster calculation. Default ist \code{TRUE}.
#' @param ... additional arguments
#' @return [\code{named list}] \code{\link[topiclabels:as.lm_topic_labels]{lm_topic_labels}} object.
#'
#' @examples
#' \dontrun{
#' token = "" # please insert your hf token here
#' topwords_matrix = matrix(c("zidane", "figo", "kroos",
#'                            "gas", "power", "wind"), ncol = 2)
#' label_topics(topwords_matrix, token = token)
#' label_topics(list(c("zidane", "figo", "kroos"),
#'                   c("gas", "power", "wind")),
#'              token = token)
#' label_topics(list(c("zidane", "figo", "ronaldo"),
#'                   c("gas", "power", "wind")),
#'              token = token)
#'
#' label_topics(list("wind", "greta", "hambach"),
#'              token = token)
#' label_topics(list("wind", "fire", "air"),
#'              token = token)
#' label_topics(list("wind", "feuer", "luft"),
#'              token = token)
#' label_topics(list("wind", "feuer", "luft"),
#'              context = "Elements of the Earth",
#'              token = token)
#' }
#' @export label_topics

label_topics = function(...) UseMethod("label_topics")

#' @rdname label_topics
#' @export
label_topics.default = function(
    terms,
    model = "mistralai/Mixtral-8x7B-Instruct-v0.1",
    params = list(),
    token = NA_character_,
    context = "",
    sep_terms = "; ",
    max_length_label = 5L,
    prompt_type = c("json", "plain", "json-roles"),
    max_wait = 0L,
    progress = TRUE, ...){

  prompt_type = match.arg(prompt_type)
  params = c(params, .default_model_params(model))
  params = params[!duplicated(names(params))]

  # BTM support:
  if(is.list(terms) & inherits(terms[[1]], "data.frame")){
    terms = lapply(terms, function(y){paste(y$token, collapse = ", ")})
  }

  if(!is.list(terms)){
    if(is.matrix(terms)) terms = unname(as.list(as.data.frame(terms)))
    else terms = list(terms)
  }
  k = length(terms)

  assert_list(terms, types = "character", any.missing = FALSE, len = k)
  for(i in seq_along(terms)){
    assert_character(terms[[i]], any.missing = FALSE)
  }
  assert_character(model, len = 1, any.missing = FALSE)
  assert_list(params, any.missing = FALSE, names = "unique")
  assert_character(token, len = 1)
  assert_character(context, len = 1, any.missing = FALSE)
  assert_character(sep_terms, len = 1, any.missing = FALSE)
  assert_int(max_length_label)
  assert_character(prompt_type, len = 1, any.missing = FALSE)
  assert_int(max_wait)
  assert_logical(progress, len = 1, any.missing = FALSE)

  model_output = character(k)
  prompts = sapply(terms, function(x)
    generate_standard_prompt(
      terms = x,
      context = context,
      sep_terms = sep_terms,
      max_length_label = max_length_label,
      type = prompt_type))
  message(paste0(
    sprintf("Labeling %s topic(s) using the language model %s", k, model),
    ifelse(!is.na(token), " and a Huggingface API token.", ".")))
  pb = .make_progress_bar(
    progress = progress,
    callback = function(x) message("Labeling process finished"),
    total = k,
    format = "Label topic :current/:total  [:bar] :percent elapsed: :elapsed eta: :eta")
  time_start = waited = Sys.time()

  for(i in seq_len(k)){
    model_output[i] = interact(model = model,
                               params = params,
                               prompt = prompts[i],
                               token = token)[[1]][[1]]
    need_hf_token_or_rate_limit =
      grepl("(please)? ?log in|(hf)? ?access token",
            model_output[i], ignore.case = TRUE) ||
      grepl("rate limit reached", model_output[i], ignore.case = TRUE)
    if(need_hf_token_or_rate_limit)
      message("Message from HuggingFace: ", model_output[i])
    while(need_hf_token_or_rate_limit){
      if(as.numeric(difftime(Sys.time(), waited, units = "mins")) > max_wait){
        max_wait = .ask_user()
        if(max_wait == 0L){
          time_end = Sys.time()
          return(as.lm_topic_labels(
            terms = terms, prompts = prompts, model = model, params = params,
            with_token = !(token == ""),
            time = as.numeric(difftime(time_end, time_start, units = "mins")),
            model_output = model_output, labels = .extract_labels(model_output, type = prompt_type)))
        }
        waited = Sys.time()
        message("Wait for five minutes", appendLF = FALSE)
        Sys.sleep(5*60) #sleep 5 minutes if rate limit is reached
      }else{
        message("\nRate limit reached - wait for one minute", appendLF = FALSE)
        Sys.sleep(60) #sleep 1 minute after each unsuccessful query
      }
      message(" - try to continue (total minutes elapsed: ",
              round(as.numeric(difftime(Sys.time(), time_start, units = "mins")), 2),
              ")", appendLF = FALSE)
      model_output[i] = interact(model = model,
                                 params = params,
                                 prompt = prompts[i],
                                 token = token)[[1]][[1]]
      need_hf_token_or_rate_limit =
        grepl("(please)? ?log in|(hf)? ?access token",
              model_output[i], ignore.case = TRUE) ||
        grepl("rate limit reached", model_output[i], ignore.case = TRUE)
    }
    pb$tick()
  }
  time_end = Sys.time()

  as.lm_topic_labels(
    terms = terms, prompts = prompts, model = model, params = params, with_token = !(token == ""),
    time = as.numeric(difftime(time_end, time_start, units = "mins")),
    model_output = model_output, labels = .extract_labels(model_output, type = prompt_type))
}

#' @rdname label_topics
#' @export
# stm support:
label_topics.labelTopics = function(
    terms,
    stm_type = c("prob", "frex", "lift", "score"), ...){

  stm_type = match.arg(stm_type)
  assert_character(stm_type, len = 1, any.missing = FALSE)

  terms = apply(terms[[stm_type]], 1, paste, collapse = ", ")
  terms = as.list(terms)

  label_topics(terms = terms, ...)
}
