/******************************************************************************
PREPARAÇÃO - MACROS-CAMINHOS E INÍCIO DO LOG DE GRAVAÇÃO DOS RESULTADOS
*******************************************************************************/
* Definindo os diretórios de trabalho
local basedados     "INSERIR AQUI O CAMINHO"
local resultados	"INSERIR AQUI O CAMINHO DO LOG DE RESULTADOS"

* Fechar qualquer log aberto
capture log close

* Limpa o Stata e o Python
clear
clear python
set more off

* Fecha o log se já estiver aberto
capture log close IRDC_Resultados

* Salvar log das estatísticas descritivas e do codebook
log using "`resultados'\IRDC_UFBAAPCONT.log", replace text name ("IRDC_Resultados")

/*******************************************************************************
Projeto:            Índice de Risco de Descumprimento Contratual (IRDC)
Autor:              Moreno Souto Santiago
Fonte dos Dados:    Painel de Informações Contábeis dos Fornecedores do STJ
Ferramentas:        Stata 18 + Python (SMOTENC)
Descrição:          
Este script executa a análise preditiva do IRDC com base em dados contábeis e cadastrais
dos fornecedores do STJ. As etapas incluem:

1. **Importação e transformação dos dados**: consolidação dos indicadores contábeis,
   análise descritiva inicial e preparação da base para modelagem.

2. **Winsorização das variáveis contínuas**: aplicação do corte nos percentis 1% e 99%
   para reduzir o impacto de outliers extremos, preservando a variabilidade e robustez
   das análises subsequentes.

3. **Imputação de valores faltantes**: preenchimento de dados ausentes por média ou mediana,
   conforme o coeficiente de variação, para garantir integridade e qualidade da base.

4. **Estatísticas descritivas por grupo**: geração de tabelas de estatísticas descritivas
   (média, desvio padrão, mínimo, máximo) para empresas penalizadas e não penalizadas,
   antes e após a winsorização, facilitando análise comparativa de perfil.
   
5. **Separação das amostras em treinamento (80%) e teste (20%)**: a separação das
   amostras é realizada obedecendo a proporção exata de empresas penalizadas e não penalizadas.

6. **Balanceamento da amostra de treinamento**: aplicação da técnica SMOTENC em Python para lidar com
   desbalanceamento da variável dependente (penalização pelo STJ), com codificação de
   variáveis categóricas e posterior reintegração ao Stata.

7. **Agrupamento de CNAEs raros**: definição do mínimo de ocorrências para manter CNAE
   como categoria isolada (local freq_minima = 10). As categorias com menor frequência
   foram agrupadas sob o código -1 para reduzir a sparsidade da matriz de variáveis dummies
   e aumentar a estabilidade dos coeficientes.
 
8. **Modelagem e avaliação preditiva**:
   - Modelo logit completo (com todas as variáveis)
   - Modelos logit com seleção stepwise (a 5% e 10%)
   - Modelo com penalização LASSO
   Cada modelo é avaliado com métricas como acurácia, Kappa, NIR, teste de McNemar,
   curvas ROC e definição do ponto de corte ideal baseado na equivalência entre
   sensibilidade e especificidade. As métricas são aplicadas nos conjuntos de treinamento e teste.

Objetivo:
Identificar o melhor modelo para predição da variável binária `FoiPenalizadoSTJ`,
avaliando o poder explicativo de indicadores contábeis, porte, natureza jurídica, CNAE,
e variáveis de histórico contratual da empresa.

Última atualização: 12/06/2025
*******************************************************************************/
   

/*******************************************************************************
ETAPA 1 - IMPORTAÇÃO, ANÁLISE DESCRITIVA DAS VARIÁVEIS E TRANSFORMAÇÃO 
*******************************************************************************/
* Definindo o diretório de trabalho e importando os dados do Excel
cd "`basedados'"
import excel "Dados_novo.xlsx", sheet("Tabela 4") firstrow clear

/*******************************************************************************
1.1 - Executar estatísticas descritivas para todas as variáveis
*******************************************************************************/
summarize LiqCorrente LiqGeral LiqCorAjust SolvGeral EndGeral CompEndivid IndepFin ImobilPL ImobRecNC PtpCapTerce GiroAtivo MargOp MargLiq ROI ROE vlrcontrato QtdeCNAEsSecundarios IdadedeAnos QtePenalOutrosOrgaos

* Estatísticas descritivas separadas por penalização
by FoiPenalizadoSTJ, sort: summarize LiqCorrente LiqGeral LiqCorAjust SolvGeral EndGeral CompEndivid IndepFin ImobilPL ImobRecNC PtpCapTerce GiroAtivo MargOp MargLiq ROI ROE vlrcontrato QtdeCNAEsSecundarios IdadedeAnos QtePenalOutrosOrgaos

* Bloco para salvar as estatísticas descritivas originais por grupo
tabstat LiqCorrente LiqGeral LiqCorAjust SolvGeral EndGeral CompEndivid IndepFin ImobilPL ImobRecNC PtpCapTerce GiroAtivo MargOp MargLiq ROI ROE vlrcontrato QtdeCNAEsSecundarios IdadedeAnos QtePenalOutrosOrgaos, ///
    statistics(mean sd min max n) by(FoiPenalizadoSTJ)
	
*Bloco de estatíticas das variáveis qualitativas

tabulate Porte
tabulate NaturezaJuridica
tabulate CNAE

quietly egen cnpjs = tag(CNPJ)
tabulate FoiPenalizadoSTJ if cnpjs == 1, missing


// Frequência com percentual
tabulate Porte, missing
tabulate NaturezaJuridica, missing
tabulate CNAE, missing


tabulate Porte FoiPenalizadoSTJ, column
tabulate NaturezaJuridica FoiPenalizadoSTJ, row
tabulate CNAE FoiPenalizadoSTJ, cell


*/*******************************************************************************
1.2 – Winsorização das variáveis contínuas (antes da imputação)
*******************************************************************************/

ssc install winsor2, replace
local winsor_vars LiqCorrente LiqGeral LiqCorAjust SolvGeral EndGeral CompEndivid IndepFin ImobilPL ImobRecNC PtpCapTerce GiroAtivo MargOp MargLiq ROI ROE vlrcontrato

foreach var of local winsor_vars {
    winsor2 `var', cuts(1 99) replace
}

/*******************************************************************************
1.3 - Executar estatísticas descritivas para todas as variáveis após wisorização
*******************************************************************************/
summarize LiqCorrente LiqGeral LiqCorAjust SolvGeral EndGeral CompEndivid IndepFin ImobilPL ImobRecNC PtpCapTerce GiroAtivo MargOp MargLiq ROI ROE vlrcontrato QtdeCNAEsSecundarios IdadedeAnos QtePenalOutrosOrgaos

* Estatísticas descritivas separadas por penalização
by FoiPenalizadoSTJ, sort: summarize LiqCorrente LiqGeral LiqCorAjust SolvGeral EndGeral CompEndivid IndepFin ImobilPL ImobRecNC PtpCapTerce GiroAtivo MargOp MargLiq ROI ROE vlrcontrato QtdeCNAEsSecundarios IdadedeAnos QtePenalOutrosOrgaos

* Bloco para salvar as estatísticas descritivas após a winsorização por grupo
tabstat LiqCorrente LiqGeral LiqCorAjust SolvGeral EndGeral CompEndivid IndepFin ImobilPL ImobRecNC PtpCapTerce GiroAtivo MargOp MargLiq ROI ROE vlrcontrato QtdeCNAEsSecundarios IdadedeAnos QtePenalOutrosOrgaos, ///
    statistics(mean sd min max n) by(FoiPenalizadoSTJ)

/*******************************************************************************
1.4 - Transformação de variáveis 
*******************************************************************************/
* NÃO gerar dummies ainda — manter Porte, CNAE e NaturezaJuridica para o SMOTENC

* Ajuste apenas valores de variáveis contínuas
replace vlrcontrato = 1 if vlrcontrato == 0 | vlrcontrato == .
gen log_vlrcontrato = log(vlrcontrato)

* Dropar CNPJ antes de exportar
drop CNPJ


/*******************************************************************************
ETAPA 2 - IMPUTAÇÃO DOS VALORES FALTANTES (MISSING) COM MÉDIA OU MEDIANA
*******************************************************************************/

* Lista de variáveis com dados faltantes para imputação
local imput_vars GiroAtivo MargOp MargLiq ROI ROE RecBruta LucroBruto LucroLiquido

* Inicializar contadores
local conta_media = 0
local conta_mediana = 0

* Imputação adaptativa: média se CV <= 0.3, mediana se CV > 0.3
foreach var of local imput_vars {
    
    quietly summarize `var' if `var' > 0, detail
    local media = r(mean)
    local desvio = r(sd)
    local mediana = r(p50)

    * Calcular o Coeficiente de Variação (CV)
    local cv = `desvio' / `media'

    * Escolher método conforme o CV
    if `cv' <= 0.3 {
        replace `var' = `media' if missing(`var') | `var' == 0
        local conta_media = `conta_media' + 1
        di as result "🔧 `var': imputado com MÉDIA (CV = " %4.3f `cv' ")"
    }
    else {
        replace `var' = `mediana' if missing(`var') | `var' == 0
        local conta_mediana = `conta_mediana' + 1
        di as result "🔧 `var': imputado com MEDIANA (CV = " %4.3f `cv' ")"
    }
}

* Exibir tabela resumo
di as text "═══════════════════════════════════════════════════════════════"
di as text " Resumo da Imputação de Variáveis (Critério: CV <= 0.3 → MÉDIA)"
di as text "───────────────────────────────────────────────────────────────"
di " Variáveis imputadas com MÉDIA:   `conta_media'"
di " Variáveis imputadas com MEDIANA: `conta_mediana'"
di as text " Total de variáveis imputadas:    " `=`conta_media' + `conta_mediana''
di as text "═══════════════════════════════════════════════════════════════"


/*******************************************************************************
ETAPA 3 - SEPARAÇÃO DOS DADOS EM CONJUNTOS DE TREINAMENTO E TESTE COM PROPORÇÕES EXATAS
*******************************************************************************/
* Definir uma seed para reprodutibilidade
set seed 12345

* Gerar uma variável aleatória uniforme entre 0 e 1
generate u = runiform()

* Ordenar aleatoriamente dentro de cada classe
sort FoiPenalizadoSTJ u

* Gerar índices de observação dentro de cada classe
by FoiPenalizadoSTJ: gen obs_no = _n
by FoiPenalizadoSTJ: gen total_obs = _N

* Calcular o ponto de corte para 80% das observações
by FoiPenalizadoSTJ: gen cutoff = ceil(0.80 * total_obs)

* Criar o indicador de treinamento
gen train = 0
replace train = 1 if obs_no <= cutoff

* Verificar distribuição antes do SMOTE
tabulate FoiPenalizadoSTJ train

/*******************************************************************************
ETAPA 3.1 - SALVAR OS LABELS PARA RESTAURAR DEPOIS DO SMOTE
*******************************************************************************/
* Criar um arquivo temporário para armazenar labels
tempfile labels_backup
label save using "`labels_backup'.do", replace

/*******************************************************************************
ETAPA 3.2 - EXPORTAR BASES PARA O PYTHON (TREINO PARA SMOTE, TESTE SEPARADO)
*******************************************************************************/
* Exportar conjunto de treino
preserve
keep if train == 1
export delimited using "train_data.csv", replace
restore

* Exportar conjunto de teste
preserve
keep if train == 0
export delimited using "test_data.csv", replace
restore

/*******************************************************************************
ETAPA 4 - APLICAR SMOTENC NO PYTHON
*******************************************************************************/
python:
import pandas as pd
import numpy as np
from imblearn.over_sampling import SMOTENC
import traceback  # Para melhor tratamento de erros

print("--- Iniciando Bloco Python ---")
try:
    # Carregar conjunto de treino do Stata
    print("Carregando train_data.csv...")
    df = pd.read_csv("train_data.csv")
    print(f"Dados carregados: {df.shape[0]} linhas, {df.shape[1]} colunas")
    print("Colunas originais:", df.columns.tolist())
    print("Contagem inicial de 'FoiPenalizadoSTJ':\n", df["FoiPenalizadoSTJ"].value_counts())

    # Separar variável-alvo e explicativas
    X = df.drop(columns=["FoiPenalizadoSTJ", "train"], errors="ignore")
    y = df["FoiPenalizadoSTJ"]

    # Definir variáveis categóricas PELOS NOMES (mais robusto)
    categorical_feature_names = ['Porte', 'CNAE', 'DivisaoCNAE', 'NaturezaJuridica']

    # Verificar se as colunas existem em X
    missing_cols = [col for col in categorical_feature_names if col not in X.columns]
    if missing_cols:
        raise ValueError(f"As seguintes colunas categóricas não foram encontradas em X: {missing_cols}")

    # Obter os índices das colunas categóricas
    categorical_features_indices = [X.columns.get_loc(col) for col in categorical_feature_names]
    print(f"Índices das features categóricas: {categorical_features_indices}")
    print("Tipos das features categóricas em X:\n", X[categorical_feature_names].dtypes)

    # Ajustar k_neighbors: deve ser menor que o número de amostras da classe minoritária
    min_class_count = y.value_counts().min()
    k_neighbors_val = min(5, min_class_count - 1)
    if k_neighbors_val < 1:
        print(f"AVISO: Classe minoritária tem apenas {min_class_count} amostras. Não é possível aplicar SMOTENC com k_neighbors >= 1.")
        raise ValueError(f"Não é possível aplicar SMOTENC, k_neighbors ({k_neighbors_val}) seria menor que 1.")
    else:
        print(f"Aplicando SMOTENC com k_neighbors={k_neighbors_val}...")
        smote_nc = SMOTENC(categorical_features=categorical_features_indices,
                           random_state=42,
                           k_neighbors=k_neighbors_val)

        X_resampled, y_resampled = smote_nc.fit_resample(X, y)
        print("SMOTENC concluído.")
        print(f"Tamanho após resample: {X_resampled.shape[0]} linhas")
        print("Contagem de 'FoiPenalizadoSTJ' após resample:\n", pd.Series(y_resampled).value_counts())

        # Criar DataFrame balanceado a partir do resultado do SMOTENC
        df_resampled = pd.DataFrame(X_resampled, columns=X.columns)

        # Adicionar a variável alvo e a marcação de treino
        df_resampled["FoiPenalizadoSTJ"] = y_resampled
        df_resampled["train"] = 1

        # Verificar se as colunas categóricas foram mantidas
        print("Colunas no df_resampled final:", df_resampled.columns.tolist())
        missing_cols_after = [col for col in categorical_feature_names if col not in df_resampled.columns]
        if missing_cols_after:
            print(f"AVISO: As colunas {missing_cols_after} NÃO estão presentes após SMOTENC!")
        else:
            print("Colunas categóricas presentes após SMOTENC.")
            print("Tipos das features categóricas após SMOTENC:\n", df_resampled[categorical_feature_names].dtypes)
            print("Primeiras linhas do df_resampled:\n", df_resampled.head())

        # 🔁 Converter variáveis categóricas e salvar mapeamentos
        print("Convertendo variáveis categóricas do treino para códigos numéricos e salvando mapeamentos...")

        categorical_mappings = {}

        for col in categorical_feature_names:
            df_resampled[col] = df_resampled[col].astype("category")

            # Salvar mapeamento antes de converter para códigos
            mapping = dict(enumerate(df_resampled[col].cat.categories))
            categorical_mappings[col] = mapping

            # Substituir coluna por códigos numéricos
            df_resampled[col] = df_resampled[col].cat.codes

            # Exportar mapeamento para CSV
            mapping_df = pd.DataFrame(mapping.items(), columns=[f"{col}_code", f"{col}_label"])
            mapping_df.to_csv(f"{col}_mapping.csv", index=False, encoding="utf-8")
            print(f"✅ Mapeamento salvo: {col}_mapping.csv")

        print("Conversão no treino concluída.")

    # Salvar dataset balanceado em CSV (codificado em UTF-8)
    print("Salvando train_data_balanced.csv...")
    df_resampled.to_csv("train_data_balanced.csv", index=False, encoding='utf-8')
    print("Arquivo train_data_balanced.csv salvo com sucesso.")

    # ────────────────────────────────────────────────────────────────────────
    # ✅ ETAPA EXTRA: Converter variáveis categóricas do conjunto de teste com os mesmos códigos do treino
    print("Carregando test_data.csv para conversão das variáveis categóricas...")
    df_test = pd.read_csv("test_data.csv")
    print(f"Conjunto de teste carregado: {df_test.shape[0]} linhas")

    # Verificar se as colunas categóricas estão presentes
    missing_test_cols = [col for col in categorical_feature_names if col not in df_test.columns]
    if missing_test_cols:
        raise ValueError(f"⚠️ Colunas categóricas ausentes no teste: {missing_test_cols}")

    print("Aplicando os mesmos mapeamentos do treino ao conjunto de teste...")

    for col in categorical_feature_names:
        mapping_df = pd.read_csv(f"{col}_mapping.csv", encoding="utf-8")
        mapping_dict = dict(zip(mapping_df[f"{col}_label"], mapping_df[f"{col}_code"]))

        # Aplicar o mapeamento manualmente
        df_test[col] = df_test[col].map(mapping_dict)

        # Se houver valores não encontrados no mapeamento, definir como -1
        df_test[col] = df_test[col].fillna(-1).astype(int)

        print(f"✅ Coluna '{col}' convertida com mapeamento do treino.")

    # Salvar novamente o arquivo convertido
    df_test.to_csv("test_data.csv", index=False, encoding="utf-8")
    print("Arquivo test_data.csv salvo com sucesso após conversão.")

except Exception as e:
    print("--- ERRO NO BLOCO PYTHON ---")
    print(traceback.format_exc())
    pd.DataFrame().to_csv("train_data_balanced.csv", index=False)
    print("Arquivo train_data_balanced.csv vazio criado devido a erro.")

print("--- Fim Bloco Python ---")
end


/*******************************************************************************
ETAPA 5 - IMPORTAR NOVO CONJUNTO DE TREINO BALANCEADO NO STATA
*******************************************************************************/
clear
* Adicionado varnames(1) e case(preserve)
import delimited "train_data_balanced.csv", varnames(1) case(preserve) clear encoding("UTF-8")

* Verificar se as variáveis existem após a importação
describe Porte CNAE DivisaoCNAE NaturezaJuridica 

* Restaurar labels originais corretamente
* Certifique-se que os labels ainda são aplicáveis. SMOTE pode alterar a natureza dos dados.
* Considere recriar labels se necessário, ou pular esta etapa se causar problemas.
capture do "`labels_backup'.do"

if _rc != 0 {
    di as error "⚠️ Falha ao restaurar labels. Verificar compatibilidade após SMOTE."
}
else {
    di as text "✅ Labels restaurados com sucesso após SMOTE."
}

* Verificar balanceamento do conjunto de treino
tabulate FoiPenalizadoSTJ train

/*******************************************************************************
ETAPA 5.1 – IMPORTAR CONJUNTO DE TESTE E JUNTAR À BASE DE TREINO BALANCEADO
*******************************************************************************/
* Passo 1 – Importar o conjunto de teste separadamente e salvar como temporário
clear
* Adicionado case(preserve)
import delimited "test_data.csv", varnames(1) case(preserve) encoding("UTF-8")
tempfile testdata
save `testdata', replace // Adicionado replace para segurança

* Passo 2 – Agora importar o treino balanceado
clear
* Adicionado varnames(1) e case(preserve)
import delimited "train_data_balanced.csv", varnames(1) case(preserve) clear encoding("UTF-8")

* Passo 3 – Restaurar os labels originais (novamente, verificar necessidade/compatibilidade)
capture do "`labels_backup'.do"
if _rc != 0 {
    di as error "Falha ao restaurar labels. Verificar compatibilidade após SMOTE."
}

* Passo 4 – Juntar com o conjunto de teste
* Verificar se as variáveis categóricas existem antes de juntar
describe Porte CNAE DivisaoCNAE NaturezaJuridica
append using `testdata'

* Passo 5 – Verificar a distribuição final por treino/teste
tabulate FoiPenalizadoSTJ train

* Verificar se as variáveis existem após o append
describe Porte CNAE DivisaoCNAE NaturezaJuridica

/*******************************************************************************
ETAPA 5.1.1 – AGRUPAMENTO DE CNAEs RAROS (CATEGORIAS COM POUCA FREQUÊNCIA)
*******************************************************************************/

* Define o mínimo de ocorrências para manter CNAE como categoria isolada
local freq_minima = 10

* Cria um grupo especial para CNAEs com baixa frequência
preserve

* Guardar versão original, caso queira rastrear depois
gen CNAE_original = CNAE 

* Gerar mapa de frequência dos CNAEs
contract CNAE
gen CNAE_agrupado = CNAE
replace CNAE_agrupado = -1 if _freq < `freq_minima'
tempfile freqmap
save `freqmap', replace

restore

* Aplicar o agrupamento via merge (sem 'nogen' para capturar _merge)
merge m:1 CNAE using `freqmap', keep(master match)

* Substituir CNAE por CNAE_agrupado apenas onde houver correspondência
replace CNAE = CNAE_agrupado if _merge == 3
drop _merge CNAE_agrupado _freq

* Verifica distribuição após o agrupamento
tabulate CNAE
di as text "✅ Agrupamento de CNAEs raros concluído com base na frequência mínima de `freq_minima'."


/*******************************************************************************
ETAPA 5.2 – CONVERTER VARIÁVEIS CATEGÓRICAS PARA INTEIROS E GERAR DUMMIES (após SMOTENC)
*******************************************************************************/
* Arredondar valores para garantir categorias inteiras
* Isso pode ser necessário se o Python/SMOTE as transformou em float, mas idealmente não deveria.
* Adicione verificações para evitar erros se a variável não existir (embora agora deva existir)

capture confirm variable Porte
if _rc == 0 {
    replace Porte = round(Porte)
} 
else {
    di as error "Variável Porte ainda não encontrada antes do round!"
}

capture confirm variable CNAE
if _rc == 0 {
    replace CNAE = round(CNAE)
} 
else {
    di as error "Variável CNAE não encontrada antes do round!"
}

capture confirm variable NaturezaJuridica
if _rc == 0 {
    replace NaturezaJuridica = round(NaturezaJuridica)
} 
else {
    di as error "Variável NaturezaJuridica não encontrada antes do round!"
}


capture confirm variable DivisaoCNAE
if _rc == 0 {
    replace DivisaoCNAE = round(DivisaoCNAE)
} 
else {
    di as error "Variável DivisaoCNAE não encontrada antes do round!"
}

* Gerar variáveis dummies
* Adicione verificações aqui também
capture confirm variable Porte
if _rc == 0 {
    tabulate Porte, generate(Porte_)
    drop Porte // Dropar original apenas se as dummies foram criadas
} 
else {
     di as error "Não foi possível gerar dummies para Porte."
}

capture confirm variable CNAE
if _rc == 0 {
    tabulate CNAE, generate(CNAE_)
    drop CNAE
} 
else {
     di as error "Não foi possível gerar dummies para CNAE."
}

capture confirm variable DivisaoCNAE
if _rc == 0 {
    tabulate DivisaoCNAE, generate(DivisaoCNAE_)
    drop DivisaoCNAE
} 
else {
     di as error "Não foi possível gerar dummies para Divisão do CNAE."
}

capture confirm variable NaturezaJuridica
if _rc == 0 {
    tabulate NaturezaJuridica, generate(NaturezaJuridica_)
    drop NaturezaJuridica
} 
else {
     di as error "Não foi possível gerar dummies para NaturezaJuridica."
}


/*******************************************************************************
ETAPA 6 - O CONJUNTO DE TESTE PERMANECE SEPARADO 
*******************************************************************************/
* O conjunto de teste ainda está salvo em "test_data.csv"
* Ele será importado separadamente no final da análise.

/******************************************************************************
Fornecer descrição básica da estrutura do conjunto de dados
*******************************************************************************/
describe

/*******************************************************************************
ETAPA 6 - ANÁLISE LOGIT

A variável dependente é 'FoiPenalizadoSTJ', do tipo binária.
Ela indica se o fornecedor foi penalizado pelo STJ (1) ou não (0).

As variáveis independentes serão divididas em variáveis contábeis e variáveis de controle.

*******************************************************************************/
* 6.1 Listar todas as variáveis disponíveis
ds

* Capturar todas as variáveis que começam com "Porte_"
unab Porte_vars : Porte_*

* Capturar todas as variáveis que começam com "CNAE_"
unab CNAE_vars : CNAE_*

* Capturar todas as variáveis que começam com "NaturezaJuridica_"
unab Natureza_vars : NaturezaJuridica_*

* Definir variáveis contábeis e de controle corretamente
local var_contabeis `Porte_vars' LiqCorrente LiqGeral LiqCorAjust SolvGeral EndGeral CompEndivid IndepFin ImobilPL ImobRecNC PtpCapTerce GiroAtivo MargOp MargLiq ROI ROE

local var_controle `CNAE_vars' `Natureza_vars' log_vlrcon~o  QtdeCNAEsS~s IdadedeAnos QtePenalOu~s

*local var_controle log_vlrcontrato `Natureza_vars' qtdecnaess~s idadedeanos qtepenalou~s

* Executar a regressão logística
logit FoiPenalizadoSTJ `var_contabeis' `var_controle' if train == 1

* Armazenar os resultados do modelo completo
estimates store IRDCcompleto

/*******************************************************************************
Justificativa das Variáveis de Controle:

- **CNAE (Classificação Nacional de Atividades Econômicas)**: Diferentes setores econômicos possuem níveis distintos de regulação e riscos operacionais. Incluir o CNAE permite controlar os efeitos específicos de cada setor na probabilidade de penalização.

- **Natureza Jurídica**: Empresas com diferentes naturezas jurídicas têm estruturas legais e de governança distintas, o que pode influenciar a conformidade regulatória e o risco de penalidades.

- **log_vlrcontrato (Log do Valor do Contrato)**: Contratos de maior valor podem estar sujeitos a maior escrutínio e complexidade, aumentando o risco de penalidades. O logaritmo é usado para linearizar a relação.

- **QtdeCNAEsSecundarios (Quantidade de CNAEs Secundários)**: Indica o nível de diversificação das atividades da empresa. Empresas mais diversificadas podem ter estruturas mais complexas, afetando a gestão e a conformidade regulatória.

- **IdadedeAnos (Idade da Empresa em Anos)**: Empresas mais antigas podem ter processos mais estabelecidos e experiência acumulada, afetando positivamente a conformidade com normas e regulamentos.

- **QtePenalOutrosOrgaos (Quantidade de Penalidades Aplicadas por Outros Órgãos)**: Um histórico de penalidades pode indicar padrões de não conformidade, aumentando a probabilidade de novas penalizações.

Essas variáveis de controle são importantes para isolar o efeito das variáveis contábeis principais, garantindo que os resultados do modelo reflitam o impacto dos indicadores contábeis na probabilidade de penalização, independentemente de outros fatores externos.

*******************************************************************************/

/*******************************************************************************
6.1.1 Teste de Bondade de Ajuste de Hosmer-Lemeshow para o modelo completo na base de treinamento
*******************************************************************************/
estat gof if train == 1, group(10) table

/*******************************************************************************
6.1.2 Tabela de classificação para o modelo completo na base de treinamento
*******************************************************************************/
estat class if train == 1

* 📌 Gerar predições na base de treinamento
capture drop prob_pred_treino
predict prob_pred_treino if train == 1, pr

* 📌 Classificação prevista
capture drop predicted_class_treino
gen predicted_class_treino = (prob_pred_treino >= 0.5) if train == 1

* 📌 Kappa na base de treinamento
*ssc install kappaetc, replace
kappaetc FoiPenalizadoSTJ predicted_class_treino if train == 1

* 📌 Acurácia na base de treinamento
capture drop correct_classification_treino
gen correct_classification_treino = (FoiPenalizadoSTJ == predicted_class_treino) if train == 1
sum correct_classification_treino if train == 1
scalar prop_modelo_treino = r(mean)

* 📌 No Information Rate (NIR)
*O NIR representa a acurácia de um modelo nulo (baseline), que classifica sempre a categoria mais frequente.
tabulate FoiPenalizadoSTJ if train == 1, matcell(freq_treino)
scalar total_treino = freq_treino[1,1] + freq_treino[2,1]
scalar max_treino = max(freq_treino[1,1], freq_treino[2,1])
scalar prop_nir_treino = max_treino / total_treino

* 📌 Comparação
di "Acurácia na base de treinamento: " prop_modelo_treino
di "NIR (treinamento): " prop_nir_treino

if (prop_modelo_treino > prop_nir_treino) {
    di "✅ Modelo completo supera o NIR na base de treino."
}
else {
    di "⚠️ Modelo completo NÃO supera o NIR na base de treino."
}

* 📌 Teste de McNemar na base de treinamento
* Criar a matriz de confusão da base de teste
tabulate FoiPenalizadoSTJ predicted_class_treino if train == 1, matcell(mc_treino)

* Extrair os valores da matriz
scalar tn_treino = mc_treino[1,1] // Verdadeiro Negativo
scalar fn_treino = mc_treino[2,1] // Falso Negativo
scalar fp_treino = mc_treino[1,2] // Falso Positivo
scalar tp_treino = mc_treino[2,2] // Verdadeiro Positivo

* Mostrar os valores extraídos (opcional)
di "TN: " tn_treino
di "FN: " fn_treino
di "FP: " fp_treino
di "TP: " tp_treino

* Rodar o teste de McNemar com os valores numéricos
mcci `=tn_treino' `=fn_treino' `=fp_treino' `=tp_treino'

/*******************************************************************************
6.1.3 Curva ROC para o modelo completo na base de TREINO
*******************************************************************************/
lroc if train == 1
graph export "lroc_IRDCcompleto_treino.png", replace

/*******************************************************************************
6.1.5 Tabela de classificação para o modelo completo na base de TESTE
*******************************************************************************/
estat class if train == 0

* 📌 Gerar predições na base de treinamento
capture drop prob_pred_teste
predict prob_pred_teste if train == 0, pr

* 📌 Classificação prevista
capture drop predicted_class_teste
gen predicted_class_teste = (prob_pred_teste >= 0.5) if train == 0

* 📌 Kappa na base de treinamento
kappaetc FoiPenalizadoSTJ predicted_class_teste if train == 0

* 📌 Acurácia na base de treinamento
capture drop correct_classification_teste
gen correct_classification_teste = (FoiPenalizadoSTJ == predicted_class_teste) if train == 0
sum correct_classification_teste if train == 0
scalar prop_modelo_teste = r(mean)

* 📌 No Information Rate (NIR)
tabulate FoiPenalizadoSTJ if train == 0, matcell(freq_teste)
scalar total_teste = freq_teste[1,1] + freq_teste[2,1]
scalar max_teste = max(freq_teste[1,1], freq_teste[2,1])
scalar prop_nir_teste = max_teste / total_teste


* 📌 Comparação
di "Acurácia na base de teste: " prop_modelo_teste
di "NIR (teste): " prop_nir_teste

if (prop_modelo_teste > prop_nir_teste) {
    di "✅ Modelo completo supera o NIR na base de teste."
}
else {
    di "⚠️ Modelo completo NÃO supera o NIR na base de teste."
}

* 📌 Teste de McNemar na base de teste
* Criar a matriz de confusão da base de teste
tabulate FoiPenalizadoSTJ predicted_class_teste if train == 0, matcell(mc_teste)

* Extrair os valores da matriz
scalar tn_teste = mc_teste[1,1] // Verdadeiro Negativo
scalar fn_teste = mc_teste[2,1] // Falso Negativo
scalar fp_teste = mc_teste[1,2] // Falso Positivo
scalar tp_teste = mc_teste[2,2] // Verdadeiro Positivo

* Mostrar os valores extraídos (opcional)
di "TN: " tn_teste
di "FN: " fn_teste
di "FP: " fp_teste
di "TP: " tp_teste

* Rodar o teste de McNemar com os valores numéricos
mcci `=tn_teste' `=fn_teste' `=fp_teste' `=tp_teste'

/*******************************************************************************
6.1.6 Curva ROC para o modelo completo na base de TESTE
*******************************************************************************/
lroc if train == 0
graph export "lroc_IRDCcompleto_teste.png", replace

/*******************************************************************************
6.1.7 – Ponto de Corte Ideal (Sensibilidade ≈ Especificidade)
*******************************************************************************/

* Reexecutar rapidamente o modelo (sem sobrescrever)
quietly logit FoiPenalizadoSTJ `var_contabeis' `var_controle' if train == 1

* Restaurar modelo salvo
estimates restore IRDCcompleto

* 📌 BASE DE TREINAMENTO
* ------------------------------------------------------------
* Garantir que as variáveis temporárias não existam
capture drop prob_pred_treino
capture drop cutoff
capture drop sens
capture drop spec
capture drop difference
capture drop abs_diff
capture drop ordem

* Gerar predições
predict prob_pred_treino if train == 1, pr

* Gerar sensitividade e especificidade para diferentes cutoffs
lsens if train == 1, genprob(cutoff) gensens(sens) genspec(spec) nograph

* Calcular diferença entre sensibilidade e especificidade
gen difference = sens - spec
gen abs_diff = abs(difference)

* Obter ponto ideal (menor diferença)
gen ordem = _n
gsort abs_diff

* Salvar valores do melhor ponto em scalars usando summarize
summarize cutoff if abs_diff == abs_diff[1]
scalar cutoff_ideal_treino = r(mean)
scalar cutoff_completo = cutoff_ideal_treino

summarize sens if abs_diff == abs_diff[1]
scalar sens_ideal_treino = r(mean)

summarize spec if abs_diff == abs_diff[1]
scalar spec_ideal_treino = r(mean)

* Mostrar o ponto ideal encontrado
list cutoff sens spec abs_diff in 1, noobs clean

* Plotar gráfico com destaque no ponto de cruzamento
lsens if train == 1, ///
    yline(`=sens_ideal_treino') xline(`=cutoff_ideal_treino') ///
    scheme(s1color) ///
    ylab(0 0.2 `=sens_ideal_treino' 0.8 1) ///
    xlab(0 0.2 `=cutoff_ideal_treino' 0.8 1)

graph export "cutoff_ideal_treino.png", replace

/*******************************************************************************
6.1.8 – Tabela de Classificação com Cutoff Ideal (Treinamento e Teste)
*******************************************************************************/

* 📌 BASE DE TREINAMENTO
* ------------------------------------------------------------

di "Tabela de classificação utilizando o cutoff ideal da base de TREINAMENTO: " cutoff_ideal_treino

* Gerar classificação com o cutoff ideal
capture drop predicted_class_treino
gen predicted_class_treino = (prob_pred_treino >= cutoff_ideal_treino) if train == 1

* Matriz de classificação detalhada
estat class if train == 1

* Kappa
kappaetc FoiPenalizadoSTJ predicted_class_treino if train == 1

* Acurácia
capture drop correct_classification_treino
gen correct_classification_treino = (FoiPenalizadoSTJ == predicted_class_treino) if train == 1
sum correct_classification_treino if train == 1
scalar prop_modelo_treino = r(mean)

* No Information Rate
tabulate FoiPenalizadoSTJ if train == 1, matcell(freq_treino)
scalar total_treino = freq_treino[1,1] + freq_treino[2,1]
scalar max_treino = max(freq_treino[1,1], freq_treino[2,1])
scalar prop_nir_treino = max_treino / total_treino

di "Acurácia (treino): " prop_modelo_treino
di "NIR (treino): " prop_nir_treino

if (prop_modelo_treino > prop_nir_treino) {
    di "✅ Modelo supera o NIR na base de treino (cutoff ideal)."
}
else {
    di "⚠️ Modelo NÃO supera o NIR na base de treino (cutoff ideal)."
}

* Teste de McNemar
tabulate FoiPenalizadoSTJ predicted_class_treino if train == 1, matcell(mc_treino)
scalar tn_treino = mc_treino[1,1]
scalar fn_treino = mc_treino[2,1]
scalar fp_treino = mc_treino[1,2]
scalar tp_treino = mc_treino[2,2]
mcci `=tn_treino' `=fn_treino' `=fp_treino' `=tp_treino'


* 📌 BASE DE TESTE
* ------------------------------------------------------------

di "Tabela de classificação utilizando o cutoff ideal da base de TREINAMENTO (aplicado na base de TESTE): " cutoff_ideal_treino

* Gerar classificação com o mesmo cutoff da base de treino
capture drop predicted_class_teste
gen predicted_class_teste = (prob_pred_teste >= cutoff_ideal_treino) if train == 0

* Matriz de classificação detalhada
estat class if train == 0

* Kappa
kappaetc FoiPenalizadoSTJ predicted_class_teste if train == 0

* Acurácia
capture drop correct_classification_teste
gen correct_classification_teste = (FoiPenalizadoSTJ == predicted_class_teste) if train == 0
sum correct_classification_teste if train == 0
scalar prop_modelo_teste = r(mean)

* No Information Rate
tabulate FoiPenalizadoSTJ if train == 0, matcell(freq_teste)
scalar total_teste = freq_teste[1,1] + freq_teste[2,1]
scalar max_teste = max(freq_teste[1,1], freq_teste[2,1])
scalar prop_nir_teste = max_teste / total_teste

di "Acurácia (teste): " prop_modelo_teste
di "NIR (teste): " prop_nir_teste

if (prop_modelo_teste > prop_nir_teste) {
    di "✅ Modelo supera o NIR na base de teste (cutoff ideal do treino)."
}
else {
    di "⚠️ Modelo NÃO supera o NIR na base de teste (cutoff ideal do treino)."
}

* Teste de McNemar
tabulate FoiPenalizadoSTJ predicted_class_teste if train == 0, matcell(mc_teste)
scalar tn_teste = mc_teste[1,1]
scalar fn_teste = mc_teste[2,1]
scalar fp_teste = mc_teste[1,2]
scalar tp_teste = mc_teste[2,2]
mcci `=tn_teste' `=fn_teste' `=fp_teste' `=tp_teste'


/*******************************************************************************
6.2 Regressão logística com seleção stepwise a 5% de significância no conjunto de treinamento
*******************************************************************************/
* Capturar todas as variáveis que começam com "Porte_"
unab Porte_vars : Porte_*

* Capturar todas as variáveis que começam com "CNAE_"
unab CNAE_vars : CNAE_*

* Capturar todas as variáveis que começam com "NaturezaJuridica_"
unab Natureza_vars : NaturezaJuridica_*

* Definir variáveis contábeis e de controle corretamente
local var_contabeis `Porte_vars' LiqCorrente LiqGeral LiqCorAjust SolvGeral EndGeral CompEndivid IndepFin ImobilPL ImobRecNC PtpCapTerce GiroAtivo MargOp MargLiq ROI ROE

*local var_controle `CNAE_vars' `Natureza_vars' log_vlrcontrato qtdecnaess~s idadedeanos qtepenalou~s

local var_controle `CNAE_vars' `Natureza_vars' log_vlrcon~o  QtdeCNAEsS~s IdadedeAnos QtePenalOu~s

*Regressão logística com seleção stepwise a 5% 
sw, pr(.05): logit FoiPenalizadoSTJ `var_contabeis' `var_controle' if train == 1

* Armazenar os resultados do modelo stepwise a 5%
estimates store IRDC05

* Teste de bondade de ajuste de Hosmer-Lemeshow para o modelo stepwise a 5%
estat gof if train == 1, group(10) table


/*******************************************************************************
6.2.2 Tabela de classificação para o modelo stepwise a 5% na base de treinamento
*******************************************************************************/
estat class if train == 1

* 📌 Gerar predições na base de treinamento
capture drop prob_pred_treino
predict prob_pred_treino if train == 1, pr

* 📌 Classificação prevista
capture drop predicted_class_treino
gen predicted_class_treino = (prob_pred_treino >= 0.5) if train == 1

* 📌 Kappa na base de treinamento
*ssc install kappaetc, replace
kappaetc FoiPenalizadoSTJ predicted_class_treino if train == 1

* 📌 Acurácia na base de treinamento
capture drop correct_classification_treino
gen correct_classification_treino = (FoiPenalizadoSTJ == predicted_class_treino) if train == 1
sum correct_classification_treino if train == 1
scalar prop_modelo_treino = r(mean)

* 📌 No Information Rate (NIR)
*O NIR representa a acurácia de um modelo nulo (baseline), que classifica sempre a categoria mais frequente.
tabulate FoiPenalizadoSTJ if train == 1, matcell(freq_treino)
scalar total_treino = freq_treino[1,1] + freq_treino[2,1]
scalar max_treino = max(freq_treino[1,1], freq_treino[2,1])
scalar prop_nir_treino = max_treino / total_treino

* 📌 Comparação
di "Acurácia na base de treinamento: " prop_modelo_treino
di "NIR (treinamento): " prop_nir_treino

if (prop_modelo_treino > prop_nir_treino) {
    di "✅ Modelo stepwise 5% supera o NIR na base de treino."
}
else {
    di "⚠️ Modelo stepwise 5% NÃO supera o NIR na base de treino."
}

* 📌 Teste de McNemar na base de treinamento
* Criar a matriz de confusão da base de teste
tabulate FoiPenalizadoSTJ predicted_class_treino if train == 1, matcell(mc_treino)

* Extrair os valores da matriz
scalar tn_treino = mc_treino[1,1] // Verdadeiro Negativo
scalar fn_treino = mc_treino[2,1] // Falso Negativo
scalar fp_treino = mc_treino[1,2] // Falso Positivo
scalar tp_treino = mc_treino[2,2] // Verdadeiro Positivo

* Mostrar os valores extraídos (opcional)
di "TN: " tn_treino
di "FN: " fn_treino
di "FP: " fp_treino
di "TP: " tp_treino

* Rodar o teste de McNemar com os valores numéricos
mcci `=tn_treino' `=fn_treino' `=fp_treino' `=tp_treino'

/*******************************************************************************
6.2.3 Curva ROC para o modelo stepwise a 5% na base de TREINO
*******************************************************************************/
lroc if train == 1
graph export "lroc_IRDC05_treino.png", replace

/*******************************************************************************
6.2.5 Tabela de classificação para o modelo stepwise a 5% na base de TESTE
*******************************************************************************/
estat class if train == 0

* 📌 Gerar predições na base de teste
capture drop prob_pred_teste
predict prob_pred_teste if train == 0, pr

* 📌 Classificação prevista
capture drop predicted_class_teste
gen predicted_class_teste = (prob_pred_teste >= 0.5) if train == 0

* 📌 Kappa na base de teste
kappaetc FoiPenalizadoSTJ predicted_class_teste if train == 0

* 📌 Acurácia na base de teste
capture drop correct_classification_teste
gen correct_classification_teste = (FoiPenalizadoSTJ == predicted_class_teste) if train == 0
sum correct_classification_teste if train == 0
scalar prop_modelo_teste = r(mean)

* 📌 No Information Rate (NIR)
tabulate FoiPenalizadoSTJ if train == 0, matcell(freq_teste)
scalar total_teste = freq_teste[1,1] + freq_teste[2,1]
scalar max_teste = max(freq_teste[1,1], freq_teste[2,1])
scalar prop_nir_teste = max_teste / total_teste


* 📌 Comparação
di "Acurácia na base de teste: " prop_modelo_teste
di "NIR (teste): " prop_nir_teste

if (prop_modelo_teste > prop_nir_teste) {
    di "✅ Modelo stepwise 5% supera o NIR na base de teste."
}
else {
    di "⚠️ Modelo stepwise 5% NÃO supera o NIR na base de teste."
}

* 📌 Teste de McNemar na base de teste
* Criar a matriz de confusão da base de teste
tabulate FoiPenalizadoSTJ predicted_class_teste if train == 0, matcell(mc_teste)

* Extrair os valores da matriz
scalar tn_teste = mc_teste[1,1] // Verdadeiro Negativo
scalar fn_teste = mc_teste[2,1] // Falso Negativo
scalar fp_teste = mc_teste[1,2] // Falso Positivo
scalar tp_teste = mc_teste[2,2] // Verdadeiro Positivo

* Mostrar os valores extraídos (opcional)
di "TN: " tn_teste
di "FN: " fn_teste
di "FP: " fp_teste
di "TP: " tp_teste

* Rodar o teste de McNemar com os valores numéricos
mcci `=tn_teste' `=fn_teste' `=fp_teste' `=tp_teste'

/*******************************************************************************
6.2.6 Curva ROC para o modelo stepwise a 5% na base de TESTE
*******************************************************************************/
lroc if train == 0
graph export "lroc_IRDC05_teste.png", replace

/*******************************************************************************
6.2.7 – Ponto de Corte Ideal (Sensibilidade ≈ Especificidade)
*******************************************************************************/

* Reexecutar rapidamente o modelo (sem sobrescrever)
quietly logit FoiPenalizadoSTJ `var_contabeis' `var_controle' if train == 1

* Restaurar modelo salvo
estimates restore IRDC05

* 📌 BASE DE TREINAMENTO
* ------------------------------------------------------------
* Garantir que as variáveis temporárias não existam
capture drop prob_pred_treino
capture drop cutoff
capture drop sens
capture drop spec
capture drop difference
capture drop abs_diff
capture drop ordem

* Gerar predições
predict prob_pred_treino if train == 1, pr

* Gerar sensitividade e especificidade para diferentes cutoffs
lsens if train == 1, genprob(cutoff) gensens(sens) genspec(spec) nograph

* Calcular diferença entre sensibilidade e especificidade
gen difference = sens - spec
gen abs_diff = abs(difference)

* Obter ponto ideal (menor diferença)
gen ordem = _n
gsort abs_diff

* Salvar valores do melhor ponto em scalars usando summarize
summarize cutoff if abs_diff == abs_diff[1]
scalar cutoff_ideal_treino = r(mean)
scalar cutoff_step05 = cutoff_ideal_treino


summarize sens if abs_diff == abs_diff[1]
scalar sens_ideal_treino = r(mean)

summarize spec if abs_diff == abs_diff[1]
scalar spec_ideal_treino = r(mean)

* Mostrar o ponto ideal encontrado
list cutoff sens spec abs_diff in 1, noobs clean

* Plotar gráfico com destaque no ponto de cruzamento
lsens if train == 1, ///
    yline(`=sens_ideal_treino') xline(`=cutoff_ideal_treino') ///
    scheme(s1color) ///
    ylab(0 0.2 `=sens_ideal_treino' 0.8 1) ///
    xlab(0 0.2 `=cutoff_ideal_treino' 0.8 1)

graph export "cutoff_ideal_IRDC05_treino.png", replace

/*******************************************************************************
6.2.8 – Tabela de Classificação com Cutoff Ideal (Treinamento e Teste)
*******************************************************************************/

* 📌 BASE DE TREINAMENTO
* ------------------------------------------------------------

di "Tabela de classificação utilizando o cutoff ideal da base de TREINAMENTO: " cutoff_ideal_treino

* Gerar classificação com o cutoff ideal
capture drop predicted_class_treino
gen predicted_class_treino = (prob_pred_treino >= cutoff_ideal_treino) if train == 1

* Matriz de classificação detalhada
estat class if train == 1

* Kappa
kappaetc FoiPenalizadoSTJ predicted_class_treino if train == 1

* Acurácia
capture drop correct_classification_treino
gen correct_classification_treino = (FoiPenalizadoSTJ == predicted_class_treino) if train == 1
sum correct_classification_treino if train == 1
scalar prop_modelo_treino = r(mean)

* No Information Rate
tabulate FoiPenalizadoSTJ if train == 1, matcell(freq_treino)
scalar total_treino = freq_treino[1,1] + freq_treino[2,1]
scalar max_treino = max(freq_treino[1,1], freq_treino[2,1])
scalar prop_nir_treino = max_treino / total_treino

di "Acurácia (treino): " prop_modelo_treino
di "NIR (treino): " prop_nir_treino

if (prop_modelo_treino > prop_nir_treino) {
    di "✅ Modelo stepwise 5% supera o NIR na base de treino (cutoff ideal)."
}
else {
    di "⚠️ Modelo stepwise 5% NÃO supera o NIR na base de treino (cutoff ideal)."
}

* Teste de McNemar
tabulate FoiPenalizadoSTJ predicted_class_treino if train == 1, matcell(mc_treino)
scalar tn_treino = mc_treino[1,1]
scalar fn_treino = mc_treino[2,1]
scalar fp_treino = mc_treino[1,2]
scalar tp_treino = mc_treino[2,2]
mcci `=tn_treino' `=fn_treino' `=fp_treino' `=tp_treino'


* 📌 BASE DE TESTE
* ------------------------------------------------------------

di "Tabela de classificação utilizando o cutoff ideal da base de TREINAMENTO (aplicado na base de TESTE): " cutoff_ideal_treino

* Gerar classificação com o mesmo cutoff da base de teste
capture drop predicted_class_teste
gen predicted_class_teste = (prob_pred_teste >= cutoff_ideal_treino) if train == 0

* Matriz de classificação detalhada
estat class if train == 0

* Kappa
kappaetc FoiPenalizadoSTJ predicted_class_teste if train == 0

* Acurácia
capture drop correct_classification_teste
gen correct_classification_teste = (FoiPenalizadoSTJ == predicted_class_teste) if train == 0
sum correct_classification_teste if train == 0
scalar prop_modelo_teste = r(mean)

* No Information Rate
tabulate FoiPenalizadoSTJ if train == 0, matcell(freq_teste)
scalar total_teste = freq_teste[1,1] + freq_teste[2,1]
scalar max_teste = max(freq_teste[1,1], freq_teste[2,1])
scalar prop_nir_teste = max_teste / total_teste

di "Acurácia (teste): " prop_modelo_teste
di "NIR (teste): " prop_nir_teste

if (prop_modelo_teste > prop_nir_teste) {
    di "✅ Modelo stepwise 5% supera o NIR na base de teste (cutoff ideal do treino)."
}
else {
    di "⚠️ Modelo stepwise 5% NÃO supera o NIR na base de teste (cutoff ideal do treino)."
}

* Teste de McNemar
tabulate FoiPenalizadoSTJ predicted_class_teste if train == 0, matcell(mc_teste)
scalar tn_teste = mc_teste[1,1]
scalar fn_teste = mc_teste[2,1]
scalar fp_teste = mc_teste[1,2]
scalar tp_teste = mc_teste[2,2]
mcci `=tn_teste' `=fn_teste' `=fp_teste' `=tp_teste'

/*******************************************************************************
6.3 Regressão logística com seleção stepwise a 10% de significância no conjunto de treinamento
*******************************************************************************/
* Capturar todas as variáveis que começam com "Porte_"
unab Porte_vars : Porte_*

* Capturar todas as variáveis que começam com "CNAE_"
unab CNAE_vars : CNAE_*

* Capturar todas as variáveis que começam com "NaturezaJuridica_"
unab Natureza_vars : NaturezaJuridica_*

* Definir variáveis contábeis e de controle corretamente
local var_contabeis `Porte_vars' LiqCorrente LiqGeral LiqCorAjust SolvGeral EndGeral CompEndivid IndepFin ImobilPL ImobRecNC PtpCapTerce GiroAtivo MargOp MargLiq ROI ROE

*local var_controle `CNAE_vars' `Natureza_vars' log_vlrcontrato qtdecnaess~s idadedeanos qtepenalou~s

local var_controle `CNAE_vars' `Natureza_vars' log_vlrcon~o  QtdeCNAEsS~s IdadedeAnos QtePenalOu~s

*Regressão logística com seleção stepwise a 10% 
sw, pr(.10): logit FoiPenalizadoSTJ `var_contabeis' `var_controle' if train == 1

* Armazenar os resultados do modelo stepwise a 10%
estimates store IRDC10

* Teste de bondade de ajuste de Hosmer-Lemeshow para o modelo stepwise a 10%
estat gof if train == 1, group(10) table

/*******************************************************************************
6.3.2 Tabela de classificação para o modelo stepwise a 10% na base de treinamento
*******************************************************************************/
estat class if train == 1

* 📌 Gerar predições na base de treinamento
capture drop prob_pred_treino
predict prob_pred_treino if train == 1, pr

* 📌 Classificação prevista
capture drop predicted_class_treino
gen predicted_class_treino = (prob_pred_treino >= 0.5) if train == 1

* 📌 Kappa na base de treinamento
*ssc install kappaetc, replace
kappaetc FoiPenalizadoSTJ predicted_class_treino if train == 1

* 📌 Acurácia na base de treinamento
capture drop correct_classification_treino
gen correct_classification_treino = (FoiPenalizadoSTJ == predicted_class_treino) if train == 1
sum correct_classification_treino if train == 1
scalar prop_modelo_treino = r(mean)

* 📌 No Information Rate (NIR)
*O NIR representa a acurácia de um modelo nulo (baseline), que classifica sempre a categoria mais frequente.
tabulate FoiPenalizadoSTJ if train == 1, matcell(freq_treino)
scalar total_treino = freq_treino[1,1] + freq_treino[2,1]
scalar max_treino = max(freq_treino[1,1], freq_treino[2,1])
scalar prop_nir_treino = max_treino / total_treino

* 📌 Comparação
di "Acurácia na base de treinamento: " prop_modelo_treino
di "NIR (treinamento): " prop_nir_treino

if (prop_modelo_treino > prop_nir_treino) {
    di "✅ Modelo stepwise 10% supera o NIR na base de treino."
}
else {
    di "⚠️ Modelo stepwise 10% NÃO supera o NIR na base de treino."
}

* 📌 Teste de McNemar na base de treinamento
* Criar a matriz de confusão da base de teste
tabulate FoiPenalizadoSTJ predicted_class_treino if train == 1, matcell(mc_treino)

* Extrair os valores da matriz
scalar tn_treino = mc_treino[1,1] // Verdadeiro Negativo
scalar fn_treino = mc_treino[2,1] // Falso Negativo
scalar fp_treino = mc_treino[1,2] // Falso Positivo
scalar tp_treino = mc_treino[2,2] // Verdadeiro Positivo

* Mostrar os valores extraídos (opcional)
di "TN: " tn_treino
di "FN: " fn_treino
di "FP: " fp_treino
di "TP: " tp_treino

* Rodar o teste de McNemar com os valores numéricos
mcci `=tn_treino' `=fn_treino' `=fp_treino' `=tp_treino'

/*******************************************************************************
6.3.3 Curva ROC para o modelo stepwise a 10% na base de TREINO
*******************************************************************************/
lroc if train == 1
graph export "lroc_IRDC10_treino.png", replace

/*******************************************************************************
6.3.4 Tabela de classificação para o modelo stepwise a 10% na base de TESTE
*******************************************************************************/
estat class if train == 0

* 📌 Gerar predições na base de teste
capture drop prob_pred_teste
predict prob_pred_teste if train == 0, pr

* 📌 Classificação prevista
capture drop predicted_class_teste
gen predicted_class_teste = (prob_pred_teste >= 0.5) if train == 0

* 📌 Kappa na base de teste
kappaetc FoiPenalizadoSTJ predicted_class_teste if train == 0

* 📌 Acurácia na base de teste
capture drop correct_classification_teste
gen correct_classification_teste = (FoiPenalizadoSTJ == predicted_class_teste) if train == 0
sum correct_classification_teste if train == 0
scalar prop_modelo_teste = r(mean)

* 📌 No Information Rate (NIR)
tabulate FoiPenalizadoSTJ if train == 0, matcell(freq_teste)
scalar total_teste = freq_teste[1,1] + freq_teste[2,1]
scalar max_teste = max(freq_teste[1,1], freq_teste[2,1])
scalar prop_nir_teste = max_teste / total_teste


* 📌 Comparação
di "Acurácia na base de teste: " prop_modelo_teste
di "NIR (teste): " prop_nir_teste

if (prop_modelo_teste > prop_nir_teste) {
    di "✅ Modelo stepwise 10% supera o NIR na base de teste."
}
else {
    di "⚠️ Modelo stepwise 10% NÃO supera o NIR na base de teste."
}

* 📌 Teste de McNemar na base de teste
* Criar a matriz de confusão da base de teste
tabulate FoiPenalizadoSTJ predicted_class_teste if train == 0, matcell(mc_teste)

* Extrair os valores da matriz
scalar tn_teste = mc_teste[1,1] // Verdadeiro Negativo
scalar fn_teste = mc_teste[2,1] // Falso Negativo
scalar fp_teste = mc_teste[1,2] // Falso Positivo
scalar tp_teste = mc_teste[2,2] // Verdadeiro Positivo

* Mostrar os valores extraídos (opcional)
di "TN: " tn_teste
di "FN: " fn_teste
di "FP: " fp_teste
di "TP: " tp_teste

* Rodar o teste de McNemar com os valores numéricos
mcci `=tn_teste' `=fn_teste' `=fp_teste' `=tp_teste'

/*******************************************************************************
6.3.5 Curva ROC para o modelo stepwise a 10% na base de TESTE
*******************************************************************************/
lroc if train == 0
graph export "lroc_IRDC10_teste.png", replace

/*******************************************************************************
6.3.6 – Ponto de Corte Ideal (Sensibilidade ≈ Especificidade)
*******************************************************************************/

* Reexecutar rapidamente o modelo (sem sobrescrever)
quietly logit FoiPenalizadoSTJ `var_contabeis' `var_controle' if train == 1

* Restaurar modelo salvo
estimates restore IRDC10

* 📌 BASE DE TREINAMENTO
* ------------------------------------------------------------
* Garantir que as variáveis temporárias não existam
capture drop prob_pred_treino
capture drop cutoff
capture drop sens
capture drop spec
capture drop difference
capture drop abs_diff
capture drop ordem

* Gerar predições
predict prob_pred_treino if train == 1, pr

* Gerar sensitividade e especificidade para diferentes cutoffs
lsens if train == 1, genprob(cutoff) gensens(sens) genspec(spec) nograph

* Calcular diferença entre sensibilidade e especificidade
gen difference = sens - spec
gen abs_diff = abs(difference)

* Obter ponto ideal (menor diferença)
gen ordem = _n
gsort abs_diff

* Salvar valores do melhor ponto em scalars usando summarize
summarize cutoff if abs_diff == abs_diff[1]
scalar cutoff_ideal_treino = r(mean)

summarize sens if abs_diff == abs_diff[1]
scalar sens_ideal_treino = r(mean)
scalar cutoff_step10 = cutoff_ideal_treino


summarize spec if abs_diff == abs_diff[1]
scalar spec_ideal_treino = r(mean)

* Mostrar o ponto ideal encontrado
list cutoff sens spec abs_diff in 1, noobs clean

* Plotar gráfico com destaque no ponto de cruzamento
lsens if train == 1, ///
    yline(`=sens_ideal_treino') xline(`=cutoff_ideal_treino') ///
    scheme(s1color) ///
    ylab(0 0.2 `=sens_ideal_treino' 0.8 1) ///
    xlab(0 0.2 `=cutoff_ideal_treino' 0.8 1)

graph export "cutoff_ideal_IRDC10_treino.png", replace

/*******************************************************************************
6.3.7 – Tabela de Classificação com Cutoff Ideal (Treinamento e Teste)
*******************************************************************************/

* 📌 BASE DE TREINAMENTO
* ------------------------------------------------------------

di "Tabela de classificação utilizando o cutoff ideal da base de TREINAMENTO: " cutoff_ideal_treino

* Gerar classificação com o cutoff ideal
capture drop predicted_class_treino
gen predicted_class_treino = (prob_pred_treino >= cutoff_ideal_treino) if train == 1

* Matriz de classificação detalhada
estat class if train == 1

* Kappa
kappaetc FoiPenalizadoSTJ predicted_class_treino if train == 1

* Acurácia
capture drop correct_classification_treino
gen correct_classification_treino = (FoiPenalizadoSTJ == predicted_class_treino) if train == 1
sum correct_classification_treino if train == 1
scalar prop_modelo_treino = r(mean)

* No Information Rate
tabulate FoiPenalizadoSTJ if train == 1, matcell(freq_treino)
scalar total_treino = freq_treino[1,1] + freq_treino[2,1]
scalar max_treino = max(freq_treino[1,1], freq_treino[2,1])
scalar prop_nir_treino = max_treino / total_treino

di "Acurácia (treino): " prop_modelo_treino
di "NIR (treino): " prop_nir_treino

if (prop_modelo_treino > prop_nir_treino) {
    di "✅ Modelo stepwise 10% supera o NIR na base de treino (cutoff ideal)."
}
else {
    di "⚠️ Modelo stepwise 10% NÃO supera o NIR na base de treino (cutoff ideal)."
}

* Teste de McNemar
tabulate FoiPenalizadoSTJ predicted_class_treino if train == 1, matcell(mc_treino)
scalar tn_treino = mc_treino[1,1]
scalar fn_treino = mc_treino[2,1]
scalar fp_treino = mc_treino[1,2]
scalar tp_treino = mc_treino[2,2]
mcci `=tn_treino' `=fn_treino' `=fp_treino' `=tp_treino'


* 📌 BASE DE TESTE
* ------------------------------------------------------------

di "Tabela de classificação utilizando o cutoff ideal da base de TREINAMENTO (aplicado na base de TESTE): " cutoff_ideal_treino

* Gerar classificação com o mesmo cutoff da base de teste
capture drop predicted_class_teste
gen predicted_class_teste = (prob_pred_teste >= cutoff_ideal_treino) if train == 0

* Matriz de classificação detalhada
estat class if train == 0

* Kappa
kappaetc FoiPenalizadoSTJ predicted_class_teste if train == 0

* Acurácia
capture drop correct_classification_teste
gen correct_classification_teste = (FoiPenalizadoSTJ == predicted_class_teste) if train == 0
sum correct_classification_teste if train == 0
scalar prop_modelo_teste = r(mean)

* No Information Rate
tabulate FoiPenalizadoSTJ if train == 0, matcell(freq_teste)
scalar total_teste = freq_teste[1,1] + freq_teste[2,1]
scalar max_teste = max(freq_teste[1,1], freq_teste[2,1])
scalar prop_nir_teste = max_teste / total_teste

di "Acurácia (teste): " prop_modelo_teste
di "NIR (teste): " prop_nir_teste

if (prop_modelo_teste > prop_nir_teste) {
    di "✅ Modelo stepwise 10% supera o NIR na base de teste (cutoff ideal do treino)."
}
else {
    di "⚠️ Modelo stepwise 10% NÃO supera o NIR na base de teste (cutoff ideal do treino)."
}

* Teste de McNemar
tabulate FoiPenalizadoSTJ predicted_class_teste if train == 0, matcell(mc_teste)
scalar tn_teste = mc_teste[1,1]
scalar fn_teste = mc_teste[2,1]
scalar fp_teste = mc_teste[1,2]
scalar tp_teste = mc_teste[2,2]
mcci `=tn_teste' `=fn_teste' `=fp_teste' `=tp_teste'

/*******************************************************************************
6.4 Teste de Razão de Verossimilhança entre os Modelos Aninhados(LR Test)
*******************************************************************************/

di "📊 Teste de Razão de Verossimilhança: IRDCcompleto vs IRDC05 (stepwise 5%)"
lrtest IRDCcompleto IRDC05

di "📊 Teste de Razão de Verossimilhança: IRDCcompleto vs IRDC10 (stepwise 10%)"
lrtest IRDCcompleto IRDC10

di "📊 Teste de Razão de Verossimilhança: IRDC05 (stepwise 5%) vs IRDC10 (stepwise 10%)"
lrtest IRDC05 IRDC10

/*******************************************************************************
6.5 Regressão logística com seleção via LASSO (penalização L1) no conjunto de treinamento

 O LASSO (Least Absolute Shrinkage and Selection Operator) realiza seleção automática
de variáveis e reduz o risco de overfitting (sobreajuste), especialmente útil em 
modelos com muitas variáveis e potencial multicolinearidade.

*******************************************************************************/

* Capturar todas as variáveis que começam com "Porte_"
unab Porte_vars : Porte_*

* Capturar todas as variáveis que começam com "CNAE_"
unab CNAE_vars : CNAE_*

* Capturar todas as variáveis que começam com "DivisaoCNAE_"
unab DivisaoCNAE_vars : DivisaoCNAE_*

* Capturar todas as variáveis que começam com "NaturezaJuridica_"
unab Natureza_vars : NaturezaJuridica_*

* Definir variáveis contábeis e de controle corretamente
local var_contabeis `Porte_vars' LiqCorrente LiqGeral LiqCorAjust SolvGeral EndGeral CompEndivid IndepFin ImobilPL ImobRecNC PtpCapTerce GiroAtivo MargOp MargLiq ROI ROE

local var_controle `CNAE_vars' `Natureza_vars' log_vlrcon~o  QtdeCNAEsS~s IdadedeAnos QtePenalOu~s

*local var_controle `DivisaoCNAE_vars' `Natureza_vars' log_vlrcon~o  QtdeCNAEsS~s IdadedeAnos QtePenalOu~s

* Consolidar todas as variáveis em uma macro
local todas_vars `var_contabeis' `var_controle'

*Ajustar modelo LASSO na base de treinamento
lasso logit FoiPenalizadoSTJ `todas_vars' if train == 1, selection(cv)

* Salvar modelo
estimates store IRDC_LASSO


/*******************************************************************************
6.5.1 – Exportar Coeficientes Selecionados do Modelo LASSO (via log + conversão via Python)
*******************************************************************************/

* Garantir que qualquer log anterior esteja fechado
capture log close lassolog

* Abrir log no diretório atual (o mesmo de execução)
log using "coef_lasso.txt", name(lassolog) text replace

* Exibir os coeficientes selecionados
lassocoef, display(coef, postselection)

* Fechar o log
log close lassolog

display "✅ coef_lasso.txt exportado com sucesso."


/*******************************************************************************
6.5.2 Tabela de Classificação, Acurácia, NIR e Teste de McNemar para o 
Modelo LASSO na base de treino
*******************************************************************************/

* 📌 Gerar predições de probabilidade na base de treinamento
capture drop prob_pred_lasso
predict prob_pred_lasso if train == 1, xb

* 📌 Classificação prevista com cutoff 0.5
capture drop pred_lasso
gen pred_lasso = (prob_pred_lasso >= 0.5) if train == 1

* 📌 Kappa
kappaetc FoiPenalizadoSTJ pred_lasso if train == 1

* 📌 Acurácia na base de treinamento
capture drop correct_lasso
gen correct_lasso = (FoiPenalizadoSTJ == pred_lasso) if train == 1
sum correct_lasso if train == 1
scalar acuracia = r(mean)

* 📌 No Information Rate (NIR)
* O NIR representa a acurácia de um modelo nulo (baseline), que classifica sempre a categoria mais frequente
tabulate FoiPenalizadoSTJ if train == 1, matcell(freq_lasso)
scalar total_lasso = freq_lasso[1,1] + freq_lasso[2,1]
scalar max_lasso = max(freq_lasso[1,1], freq_lasso[2,1])
scalar prop_nir_lasso = max_lasso / total_lasso

* 📌 Comparação
di "Acurácia LASSO na base de treinamento: " acuracia
di "NIR (treinamento): " prop_nir_lasso

if (acuracia > prop_nir_lasso) {
    di "✅ Modelo LASSO supera o NIR na base de treino."
}
else {
    di "⚠️ Modelo LASSO NÃO supera o NIR na base de treino."
}

* 📌 Teste de McNemar na base de treinamento
tabulate FoiPenalizadoSTJ pred_lasso if train == 1, matcell(mc_lasso)

scalar tn_lasso = mc_lasso[1,1] // Verdadeiro Negativo
scalar fn_lasso = mc_lasso[2,1] // Falso Negativo
scalar fp_lasso = mc_lasso[1,2] // Falso Positivo
scalar tp_lasso = mc_lasso[2,2] // Verdadeiro Positivo

* Mostrar os valores extraídos (opcional)
di "TN: " tn_lasso
di "FN: " fn_lasso
di "FP: " fp_lasso
di "TP: " tp_lasso

* Rodar o teste de McNemar com os valores numéricos
mcci `=tn_lasso' `=fn_lasso' `=fp_lasso' `=tp_lasso'

/*******************************************************************************
6.5.3 Curva ROC para o modelo LASSO na base de TREINO
*******************************************************************************/
capture drop prob_pred_lasso_treino
predict prob_pred_lasso_treino if train == 1, xb
roctab FoiPenalizadoSTJ prob_pred_lasso_treino if train == 1, graph
graph export "ROC_LASSO_treino.png", replace

/*******************************************************************************
6.5.4 Avaliação do modelo LASSO na base de TESTE
*******************************************************************************/

* 📌 Gerar predições de probabilidade na base de teste
capture drop prob_pred_lasso_teste
predict prob_pred_lasso_teste if train == 0, xb

* 📌 Classificação prevista com cutoff 0.5
capture drop pred_lasso_teste
gen pred_lasso_teste = (prob_pred_lasso_teste >= 0.5) if train == 0

* 📌 Kappa na base de teste
kappaetc FoiPenalizadoSTJ pred_lasso_teste if train == 0

* 📌 Acurácia na base de teste
capture drop correct_lasso_teste
gen correct_lasso_teste = (FoiPenalizadoSTJ == pred_lasso_teste) if train == 0
sum correct_lasso_teste if train == 0
scalar acuracia_teste = r(mean)

* 📌 No Information Rate (NIR) - TESTE
tabulate FoiPenalizadoSTJ if train == 0, matcell(freq_teste)
scalar total_teste = freq_teste[1,1] + freq_teste[2,1]
scalar max_teste = max(freq_teste[1,1], freq_teste[2,1])
scalar nir_teste = max_teste / total_teste

di "Acurácia LASSO (teste): " acuracia_teste
di "NIR (teste): " nir_teste

if (acuracia_teste > nir_teste) {
    di "✅ Modelo LASSO supera o NIR na base de teste."
}
else {
    di "⚠️ Modelo LASSO NÃO supera o NIR na base de teste."
}

* 📌 Teste de McNemar - TESTE
tabulate FoiPenalizadoSTJ pred_lasso_teste if train == 0, matcell(mc_lasso_teste)

scalar tn_teste = mc_lasso_teste[1,1]
scalar fn_teste = mc_lasso_teste[2,1]
scalar fp_teste = mc_lasso_teste[1,2]
scalar tp_teste = mc_lasso_teste[2,2]

di "TN: " tn_teste
di "FN: " fn_teste
di "FP: " fp_teste
di "TP: " tp_teste

mcci `=tn_teste' `=fn_teste' `=fp_teste' `=tp_teste'

/*******************************************************************************
6.5.5 Curva ROC para o modelo LASSO na base de TESTE
*******************************************************************************/
roctab FoiPenalizadoSTJ prob_pred_lasso_teste if train == 0, graph
graph export "ROC_LASSO_teste.png", replace

/*******************************************************************************
6.5.6 – Classificação com Cutoff Médio (modelo LASSO)
*******************************************************************************/

* 📌 Definir o cutoff médio com base nos modelos completos, stepwise 5% e stepwise 10%
scalar cutoff_medio = (cutoff_completo + cutoff_step05 + cutoff_step10) / 3
di "📌 Cutoff médio dos modelos: " cutoff_medio

* ========================================================
* BASE DE TREINAMENTO
* ========================================================

* 📌 Gerar classificação com cutoff médio
capture drop predicted_class_lasso_treino
gen predicted_class_lasso_treino = (prob_pred_lasso_treino >= cutoff_medio) if train == 1

* 📌 Matriz de classificação com tabulação
tabulate FoiPenalizadoSTJ predicted_class_lasso_treino if train == 1, matcell(mc_lasso_treino)

* 📌 Extrair valores
scalar tn_lasso_medio = mc_lasso_treino[1,1]
scalar fn_lasso_medio = mc_lasso_treino[2,1]
scalar fp_lasso_medio = mc_lasso_treino[1,2]
scalar tp_lasso_medio = mc_lasso_treino[2,2]

* 📌 Teste de McNemar
mcci `=tn_lasso_medio' `=fn_lasso_medio' `=fp_lasso_medio' `=tp_lasso_medio'

* ========================================================
* BASE DE TESTE
* ========================================================

* 📌 Gerar classificação com cutoff médio
capture drop predicted_class_lasso_teste
gen predicted_class_lasso_teste = (prob_pred_lasso_teste >= cutoff_medio) if train == 0

* 📌 Matriz de classificação com tabulação
tabulate FoiPenalizadoSTJ predicted_class_lasso_teste if train == 0, matcell(mc_lasso_teste)

* 📌 Extrair valores
scalar tn_lasso_medio_teste = mc_lasso_teste[1,1]
scalar fn_lasso_medio_teste = mc_lasso_teste[2,1]
scalar fp_lasso_medio_teste = mc_lasso_teste[1,2]
scalar tp_lasso_medio_teste = mc_lasso_teste[2,2]

* 📌 Teste de McNemar
mcci `=tn_lasso_medio_teste' `=fn_lasso_medio_teste' `=fp_lasso_medio_teste' `=tp_lasso_medio_teste'

/*******************************************************************************
FIM DO SCRIPT
*******************************************************************************/

log off